import * as vscode from 'vscode';

export type LogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR';

export interface LogEvent {
  level: LogLevel;
  component: string;
  stage: string;
  message: string;
  requestId?: string;
  durationMs?: number;
  data?: Record<string, unknown>;
}

/** Central structured logger. Open it with `Flust: Show Logs`. */
export class FlustLogger {
  private static instance: FlustLogger | undefined;
  private readonly output: vscode.OutputChannel;
  private sequence = 0;

  private constructor() {
    this.output = vscode.window.createOutputChannel('Flust', { log: true });
  }

  static get(): FlustLogger {
    return this.instance ??= new FlustLogger();
  }

  log(event: LogEvent): void {
    const record = {
      timestamp: new Date().toISOString(),
      sequence: ++this.sequence,
      ...event,
    };
    const line = JSON.stringify(record);
    this.output.appendLine(line);
  }

  debug(component: string, stage: string, message: string, data?: Record<string, unknown>, requestId?: string): void {
    this.log({ level: 'DEBUG', component, stage, message, data, requestId });
  }
  info(component: string, stage: string, message: string, data?: Record<string, unknown>, requestId?: string): void {
    this.log({ level: 'INFO', component, stage, message, data, requestId });
  }
  warn(component: string, stage: string, message: string, data?: Record<string, unknown>, requestId?: string): void {
    this.log({ level: 'WARN', component, stage, message, data, requestId });
  }
  error(component: string, stage: string, message: string, data?: Record<string, unknown>, requestId?: string): void {
    this.log({ level: 'ERROR', component, stage, message, data, requestId });
  }

  show(): void { this.output.show(true); }
  clear(): void { this.output.clear(); }
  dispose(): void { this.output.dispose(); FlustLogger.instance = undefined; }
}
