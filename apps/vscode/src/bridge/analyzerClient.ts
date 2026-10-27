import * as vscode from 'vscode';
import * as cp from 'node:child_process';
import * as readline from 'node:readline';
import * as path from 'node:path';

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
}

interface ParseResponse {
  id: string;
  ok: boolean;
  model?: FlustModel;
  error?: string;
}

export class AnalyzerClient implements vscode.Disposable {
  private process?: cp.ChildProcessWithoutNullStreams;
  private lines?: readline.Interface;
  private requestId = 0;
  private readonly pending = new Map<string, (response: ParseResponse) => void>();

  constructor(
    private readonly extensionUri: vscode.Uri
  ) {}

  async parse(uri: vscode.Uri, source: string): Promise<FlustModel> {
    const analyzerPath = this.findAnalyzer();
    if (!analyzerPath) {
      return this.fallbackModel(uri, source, 'Analyzer not found. Run `dart pub get` in tools/analyzer.');
    }

    try {
      this.ensureProcess(analyzerPath);
      const id = String(++this.requestId);
      const responsePromise = new Promise<ParseResponse>((resolve, reject) => {
        const timeout = setTimeout(() => {
          this.pending.delete(id);
          reject(new Error('Timed out waiting for Flust Analyzer.'));
        }, 10000);
        this.pending.set(id, (response) => {
          clearTimeout(timeout);
          resolve(response);
        });
      });

      this.process!.stdin.write(JSON.stringify({
        id, method: 'parse', uri: uri.toString(), source
      }) + '\n');

      const response = await responsePromise;
      if (!response.ok || !response.model) {
        throw new Error(response.error ?? 'Analyzer returned no model.');
      }
      return response.model;
    } catch (error) {
      return this.fallbackModel(uri, source, String(error));
    }
  }

  private findAnalyzer(): string {
    return path.resolve(
      this.extensionUri.fsPath,
      '..',
      '..',
      'tools',
      'analyzer',
      'bin',
      'flust_analyzer.dart'
    );
  }

  private ensureProcess(analyzerPath: string): void {
    if (this.process && this.process.exitCode === null && !this.process.killed) {
      return;
    }

    const packageRoot = path.dirname(path.dirname(analyzerPath));

    const child = cp.spawn(
      'dart',
      ['run', 'bin/flust_analyzer.dart'],
      {
        cwd: packageRoot,
        stdio: ['pipe', 'pipe', 'pipe'],
        shell: process.platform === 'win32',
        windowsHide: true
      }
    );

    this.process = child;

    this.lines?.close();
    this.lines = readline.createInterface({
      input: child.stdout
    });

    this.lines.on('line', (line: string) => {
      try {
        const response = JSON.parse(line) as ParseResponse;
        const resolve = this.pending.get(response.id);

        if (resolve) {
          this.pending.delete(response.id);
          resolve(response);
        }
      } catch {
        console.error(`[Flust Analyzer] Invalid JSON response: ${line}`);
      }
    });

    child.stderr.on('data', (chunk: Buffer) => {
      console.error(`[Flust Analyzer] ${chunk.toString().trimEnd()}`);
    });

    child.on('error', (error: Error) => {
      console.error(`[Flust Analyzer] Failed to start: ${error.message}`);

      for (const [id, resolve] of this.pending) {
        resolve({
          id,
          ok: false,
          error: `Failed to start Dart analyzer: ${error.message}`
        });
      }

      this.pending.clear();
      this.lines?.close();
      this.lines = undefined;
      this.process = undefined;
    });

    child.on('exit', (code, signal) => {
      console.error(
        `[Flust Analyzer] Exited: code=${code}, signal=${signal}`
      );

      for (const [id, resolve] of this.pending) {
        resolve({
          id,
          ok: false,
          error: `Flust Analyzer exited (code=${code}, signal=${signal}).`
        });
      }

      this.pending.clear();
      this.lines?.close();
      this.lines = undefined;
      this.process = undefined;
    });
  }

  private fallbackModel(uri: vscode.Uri, source: string, message: string): FlustModel {
    return {
      schemaVersion: 1,
      uri: uri.toString(),
      root: {
        id: 'fallback-root',
        kind: 'expression',
        name: 'Analyzer unavailable',
        source: { start: 0, end: source.length },
        properties: { message },
        children: []
      },
      diagnostics: [{ message }]
    };
  }

  dispose(): void {
    this.lines?.close();
    this.process?.kill();
    this.process = undefined;
    this.pending.clear();
  }
}
