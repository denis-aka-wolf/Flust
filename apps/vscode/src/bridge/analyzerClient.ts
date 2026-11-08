import * as vscode from 'vscode';
import * as cp from 'node:child_process';
import * as readline from 'node:readline';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { FlustLogger } from '../logging';

export interface FlustNode {
  id: string;
  kind: 'widget' | 'expression';
  name: string;
  source: { start: number; end: number };
  properties: Record<string, unknown>;
  children: FlustNode[];
}
export interface FlustModel {
  schemaVersion: number;
  uri: string;
  root: FlustNode | null;
  diagnostics: Array<{ message: string; offset?: number; length?: number }>;
  analyzer?: { status: 'ready' | 'error'; message?: string };
}
interface ParseResponse { id: string; ok: boolean; model?: FlustModel; error?: string; }
interface PendingRequest { resolve: (response: ParseResponse) => void; timer: NodeJS.Timeout; startedAt: number; }

export class AnalyzerClient implements vscode.Disposable {
  private process?: cp.ChildProcessWithoutNullStreams;
  private lines?: readline.Interface;
  private requestId = 0;
  private readonly pending = new Map<string, PendingRequest>();
  private readonly logger = FlustLogger.get();
  private readonly startupTimeoutMs = 15000;
  private readonly requestTimeoutMs = 30000;

  constructor(private readonly extensionUri: vscode.Uri) {}

  async parse(uri: vscode.Uri, source: string): Promise<FlustModel> {
    const requestId = String(++this.requestId);
    const startedAt = Date.now();
    this.logger.info('AnalyzerClient', 'parse.start', 'Parse requested', {
      uri: uri.toString(), sourceLength: source.length,
    }, requestId);

    const analyzerPath = this.findAnalyzer();
    if (!fs.existsSync(analyzerPath)) {
      const message = `Analyzer entrypoint not found: ${analyzerPath}`;
      this.logger.error('AnalyzerClient', 'analyzer.locate', message, undefined, requestId);
      return this.fallbackModel(uri, source, message);
    }
    this.logger.debug('AnalyzerClient', 'analyzer.locate', 'Analyzer entrypoint found', { analyzerPath }, requestId);

    try {
      await this.ensureProcess(analyzerPath, requestId);
      const response = await this.sendRequest(uri, source, requestId);
      if (!response.ok || !response.model) {
        throw new Error(response.error ?? 'Analyzer returned no model.');
      }
      const widgetCount = this.countWidgets(response.model.root);
      this.logger.info('AnalyzerClient', 'parse.complete', 'Parse completed', {
        durationMs: Date.now() - startedAt,
        widgetCount,
        diagnosticsCount: response.model.diagnostics?.length ?? 0,
      }, requestId);
      return { ...response.model, analyzer: { status: 'ready' } };
    } catch (error) {
      const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
      this.logger.error('AnalyzerClient', 'parse.failed', message, {
        durationMs: Date.now() - startedAt,
        processPid: this.process?.pid,
        processExitCode: this.process?.exitCode,
      }, requestId);
      return this.fallbackModel(uri, source, message);
    }
  }

  private findAnalyzer(): string {
    return path.resolve(this.extensionUri.fsPath, '..', '..', 'tools', 'analyzer', 'bin', 'flust_analyzer.dart');
  }

  private async ensureProcess(analyzerPath: string, requestId: string): Promise<void> {
    if (this.process && this.process.exitCode === null && !this.process.killed) return;
    const packageRoot = path.dirname(path.dirname(analyzerPath));
    this.logger.info('AnalyzerClient', 'process.start', 'Starting Dart Analyzer', {
      executable: 'dart', args: ['run', 'bin/flust_analyzer.dart'], cwd: packageRoot,
      platform: process.platform,
    }, requestId);

    const child = cp.spawn('dart', ['run', 'bin/flust_analyzer.dart'], {
      cwd: packageRoot,
      stdio: ['pipe', 'pipe', 'pipe'],
      windowsHide: true,
    });
    this.process = child;

    child.on('error', (error: Error) => {
      this.logger.error('AnalyzerClient', 'process.error', 'Failed to spawn Dart Analyzer', {
        message: error.message, stack: error.stack,
      }, requestId);
      this.failPending(`Failed to start Dart Analyzer: ${error.message}`);
    });
    child.on('exit', (code, signal) => {
      this.logger.error('AnalyzerClient', 'process.exit', 'Dart Analyzer process exited', {
        code, signal, pendingRequests: this.pending.size,
      }, requestId);
      this.failPending(`Dart Analyzer exited (code=${code}, signal=${signal}).`);
      this.lines?.close(); this.lines = undefined;
      if (this.process === child) this.process = undefined;
    });
    child.on('close', (code, signal) => this.logger.debug('AnalyzerClient', 'process.close', 'Dart process streams closed', { code, signal }, requestId));

    this.lines?.close();
    this.lines = readline.createInterface({ input: child.stdout });
    this.lines.on('line', line => {
      try {
        const response = JSON.parse(line) as ParseResponse;
        const pending = this.pending.get(String(response.id));
        this.logger.debug('AnalyzerProtocol', 'response.received', 'JSON response received', {
          responseId: response.id, ok: response.ok, bytes: Buffer.byteLength(line),
        }, String(response.id));
        if (pending) {
          clearTimeout(pending.timer);
          this.pending.delete(String(response.id));
          pending.resolve(response);
        } else {
          this.logger.warn('AnalyzerProtocol', 'response.unmatched', 'Response has no pending request', { responseId: response.id });
        }
      } catch (error) {
        this.logger.error('AnalyzerProtocol', 'response.invalid_json', 'Analyzer wrote invalid JSON to stdout', {
          line: line.slice(0, 2000), error: String(error),
        }, requestId);
      }
    });
    child.stderr.on('data', (chunk: Buffer) => {
      const message = chunk.toString().trimEnd();
      if (message) this.logger.info('DartAnalyzer', 'stderr', message, undefined, requestId);
    });
    child.stdout.on('data', chunk => this.logger.debug('AnalyzerProtocol', 'stdout.chunk', 'Received stdout data', { bytes: chunk.length }, requestId));

    await new Promise<void>((resolve, reject) => {
      let settled = false;
      const timer = setTimeout(() => {
        if (settled) return;
        settled = true;
        this.logger.error('AnalyzerClient', 'process.start_timeout', 'Dart Analyzer did not become available before startup timeout', {
          timeoutMs: this.startupTimeoutMs, pid: child.pid,
        }, requestId);
        reject(new Error(`Dart Analyzer startup timed out after ${this.startupTimeoutMs} ms. Check that Dart SDK is installed and available on PATH.`));
      }, this.startupTimeoutMs);
      child.once('spawn', () => {
        if (settled) return;
        settled = true; clearTimeout(timer);
        this.logger.info('AnalyzerClient', 'process.spawned', 'Dart process spawned', { pid: child.pid }, requestId);
        resolve();
      });
      child.once('error', error => {
        if (settled) return;
        settled = true; clearTimeout(timer); reject(error);
      });
    });
  }

  private sendRequest(uri: vscode.Uri, source: string, requestId: string): Promise<ParseResponse> {
    const child = this.process;
    if (!child || child.exitCode !== null || child.killed) throw new Error('Dart Analyzer process is not running.');
    const payload = JSON.stringify({ id: requestId, method: 'parse', uri: uri.toString(), source }) + '\n';
    this.logger.debug('AnalyzerProtocol', 'request.send', 'Sending parse request', {
      bytes: Buffer.byteLength(payload), sourceLength: source.length,
    }, requestId);

    return new Promise<ParseResponse>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        this.logger.error('AnalyzerProtocol', 'request.timeout', 'No response received from Dart Analyzer', {
          timeoutMs: this.requestTimeoutMs, pid: child.pid,
        }, requestId);
        reject(new Error(`Timed out waiting for Flust Analyzer after ${this.requestTimeoutMs} ms (request ${requestId}).`));
      }, this.requestTimeoutMs);
      this.pending.set(requestId, { resolve, timer, startedAt: Date.now() });
      child.stdin.write(payload, error => {
        if (error) {
          const pending = this.pending.get(requestId);
          if (pending) clearTimeout(pending.timer);
          this.pending.delete(requestId);
          this.logger.error('AnalyzerProtocol', 'request.write_failed', 'Could not write request to Analyzer stdin', { error: error.message }, requestId);
          reject(error);
        }
      });
    });
  }

  private failPending(message: string): void {
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timer);
      pending.resolve({ id, ok: false, error: message });
    }
    this.pending.clear();
  }

  private countWidgets(node: FlustNode | null): number {
    return node ? 1 + node.children.reduce((sum, child) => sum + this.countWidgets(child), 0) : 0;
  }

  private fallbackModel(uri: vscode.Uri, source: string, message: string): FlustModel {
    return {
      schemaVersion: 1, uri: uri.toString(),
      root: {
        id: 'fallback-root', kind: 'expression', name: 'Analyzer unavailable',
        source: { start: 0, end: source.length }, properties: { message }, children: [],
      },
      diagnostics: [{ message }], analyzer: { status: 'error', message },
    };
  }

  dispose(): void {
    this.logger.info('AnalyzerClient', 'dispose', 'Disposing Analyzer client', { pendingRequests: this.pending.size });
    for (const pending of this.pending.values()) clearTimeout(pending.timer);
    this.pending.clear();
    this.lines?.close();
    this.process?.kill();
    this.process = undefined;
  }
}
