import * as vscode from 'vscode';
import { FlustEditorProvider } from '../editor/flustEditorProvider';

export async function openInFlust(_context: vscode.ExtensionContext): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  const uri = editor?.document.uri ?? vscode.window.activeNotebookEditor?.notebook.uri;

  if (!uri) {
    void vscode.window.showInformationMessage('Flust: Open a Dart file first.');
    return;
  }

  if (!uri.fsPath.endsWith('.dart')) {
    void vscode.window.showWarningMessage('Flust can open Dart files ending in .dart.');
    return;
  }

  await vscode.commands.executeCommand('vscode.openWith', uri, FlustEditorProvider.viewType);
}
