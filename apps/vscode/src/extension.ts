import * as vscode from 'vscode';
import { FlustEditorProvider } from './editor/flustEditorProvider';
import { openInFlust } from './commands/openInFlust';

export function activate(context: vscode.ExtensionContext): void {
  context.subscriptions.push(
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

export function deactivate(): void {}
