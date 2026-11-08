import * as vscode from 'vscode';
import { FlustEditorProvider } from './editor/flustEditorProvider';
import { openInFlust } from './commands/openInFlust';
import { FlustLogger } from './logging';

export function activate(context: vscode.ExtensionContext): void {
  const logger = FlustLogger.get();
  logger.info('Extension', 'activate', 'Flust extension activated', { version: context.extension.packageJSON.version, extensionPath: context.extensionPath });
  context.subscriptions.push(
    { dispose: () => logger.dispose() },
    vscode.commands.registerCommand('flust.showLogs', () => logger.show()),
    vscode.commands.registerCommand('flust.clearLogs', () => logger.clear()),
    vscode.window.registerCustomEditorProvider(
      FlustEditorProvider.viewType,
      new FlustEditorProvider(context),
      {
        webviewOptions: { retainContextWhenHidden: true },
        supportsMultipleEditorsPerDocument: false
      }
    ),
    vscode.commands.registerCommand('flust.openInFlust', () => openInFlust(context))
  );
}

export function deactivate(): void {
  FlustLogger.get().info('Extension', 'deactivate', 'Flust extension deactivated');
}
