import * as vscode from 'vscode';
import { FlustDocument } from './documentManager';
import { AnalyzerClient, FlustModel } from '../bridge/analyzerClient';

export class FlustEditorProvider implements vscode.CustomEditorProvider<FlustDocument> {
  static readonly viewType = 'flust.visualEditor';

  private readonly clients = new Map<string, AnalyzerClient>();

  private readonly changeEmitter =
    new vscode.EventEmitter<vscode.CustomDocumentEditEvent<FlustDocument>>();

  readonly onDidChangeCustomDocument = this.changeEmitter.event;

  async saveCustomDocument(
    _document: FlustDocument,
    _cancellation: vscode.CancellationToken
  ): Promise<void> {
    // The visual editor is read-only for now.
    // Source editing will be implemented in a later milestone.
  }

  async saveCustomDocumentAs(
    document: FlustDocument,
    destination: vscode.Uri,
    _cancellation: vscode.CancellationToken
  ): Promise<void> {
    const content = await vscode.workspace.fs.readFile(document.uri);
    await vscode.workspace.fs.writeFile(destination, content);
  }

  async revertCustomDocument(
    _document: FlustDocument,
    _cancellation: vscode.CancellationToken
  ): Promise<void> {
    // There are no unsaved visual edits to revert yet.
  }

  async backupCustomDocument(
    document: FlustDocument,
    context: vscode.CustomDocumentBackupContext,
    _cancellation: vscode.CancellationToken
  ): Promise<vscode.CustomDocumentBackup> {
    const content = await vscode.workspace.fs.readFile(document.uri);
    await vscode.workspace.fs.writeFile(context.destination, content);

    return {
      id: context.destination.toString(),
      delete: () => {
        void vscode.workspace.fs.delete(context.destination).then(
          () => undefined,
          () => undefined
        );
      }
    };
  }


  constructor(private readonly context: vscode.ExtensionContext) {}

  async openCustomDocument(uri: vscode.Uri): Promise<FlustDocument> {
    return FlustDocument.create(uri);
  }

  async resolveCustomEditor(
    document: FlustDocument,
    webviewPanel: vscode.WebviewPanel
  ): Promise<void> {
    webviewPanel.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.context.extensionUri]
    };
    webviewPanel.webview.html = this.getHtml(webviewPanel.webview);

    const client = new AnalyzerClient(this.context.extensionUri);
    this.clients.set(document.uri.toString(), client);

    const update = async () => {
      try {
        const sourceBytes = await vscode.workspace.fs.readFile(document.uri);
        const source = new TextDecoder().decode(sourceBytes);
        const model: FlustModel = await client.parse(document.uri, source);
        webviewPanel.webview.postMessage({ type: 'model', model });
      } catch (error) {
        webviewPanel.webview.postMessage({
          type: 'error',
          message: `Could not read file: ${String(error)}`
        });
      }
    };

    webviewPanel.webview.onDidReceiveMessage(async (message) => {
      if (message?.type === 'ready') await update();
      if (message?.type === 'revealSource' && Number.isInteger(message.offset)) {
        const doc = await vscode.workspace.openTextDocument(document.uri);
        const editor = await vscode.window.showTextDocument(doc, { preview: true });
        const position = doc.positionAt(Math.max(0, Math.min(message.offset, doc.getText().length)));
        editor.selection = new vscode.Selection(position, position);
        editor.revealRange(new vscode.Range(position, position), vscode.TextEditorRevealType.InCenter);
      }
    });

    const watcher = vscode.workspace.onDidChangeTextDocument((event) => {
      if (event.document.uri.toString() === document.uri.toString()) void update();
    });
    webviewPanel.onDidDispose(() => {
      watcher.dispose();
      client.dispose();
      this.clients.delete(document.uri.toString());
    });

    await update();
  }

  private getHtml(webview: vscode.Webview): string {
    const nonce = getNonce();
    return /* html */ `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${webview.cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';">
<title>Flust Visual Editor</title>
<style>
:root { color-scheme: light dark; }
body { font-family: var(--vscode-font-family); color: var(--vscode-foreground); background: var(--vscode-editor-background); margin: 0; }
header { padding: 12px 16px; border-bottom: 1px solid var(--vscode-panel-border); display:flex; align-items:center; gap:10px; }
h1 { font-size: 16px; margin:0; } .badge { font-size:11px; opacity:.7; border:1px solid var(--vscode-panel-border); padding:3px 6px; border-radius:5px; }
main { display:grid; grid-template-columns:minmax(200px, 280px) 1fr; min-height:calc(100vh - 50px); }
aside { padding:14px; border-right:1px solid var(--vscode-panel-border); overflow:auto; }
section { padding:18px; overflow:auto; }
h2 { font-size:12px; text-transform:uppercase; letter-spacing:.08em; opacity:.75; }
ul { list-style:none; padding-left:14px; } li { margin:5px 0; }
.node { cursor:pointer; padding:5px 7px; border-radius:4px; display:inline-block; }
.node:hover { background:var(--vscode-list-hoverBackground); }
.node button { all:unset; cursor:pointer; }
.card { border:1px solid var(--vscode-panel-border); border-radius:8px; padding:16px; margin-top:10px; }
pre { white-space:pre-wrap; overflow-wrap:anywhere; font-family:var(--vscode-editor-font-family); font-size:12px; }
.muted { opacity:.7; } .error { color:var(--vscode-errorForeground); }
</style>
</head>
<body>
<header><h1>Flust</h1><span class="badge">AST Explorer · MVP</span><span id="status" class="muted">Waiting for analyzer…</span></header>
<main>
<aside><h2>Widget Tree</h2><div id="tree" class="muted">Parsing source…</div></aside>
<section><h2>Node details</h2><div id="details" class="card">Select a node in the tree.</div><h2>Diagnostics</h2><div id="diagnostics" class="card muted">No diagnostics yet.</div></section>
</main>
<script nonce="${nonce}">
const vscode = acquireVsCodeApi();
let currentModel = null;
function esc(value) { return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function renderNode(node) {
  if (!node) return '';
  const children = (node.children || []).map(renderNode).join('');
  return '<li><span class="node"><button data-id="' + esc(node.id) + '">' + esc(node.name) + '</button></span>' + (children ? '<ul>' + children + '</ul>' : '') + '</li>';
}
function flatten(node, result = []) { if (!node) return result; result.push(node); (node.children || []).forEach(child => flatten(child, result)); return result; }
function selectNode(id) {
  const node = flatten(currentModel?.root).find(item => item.id === id);
  if (!node) return;
  const props = Object.entries(node.properties || {}).map(([key, value]) => '<div><strong>' + esc(key) + ':</strong> <pre>' + esc(typeof value === 'string' ? value : JSON.stringify(value, null, 2)) + '</pre></div>').join('');
  document.getElementById('details').innerHTML = '<strong>' + esc(node.name) + '</strong><p class="muted">' + esc(node.kind) + ' · ' + node.source.start + '–' + node.source.end + '</p>' + (props || '<p class="muted">No properties extracted.</p>') + '<button id="reveal">Reveal in source</button>';
  document.getElementById('reveal').addEventListener('click', () => vscode.postMessage({type:'revealSource', offset:node.source.start}));
}
window.addEventListener('message', event => {
  const message = event.data;
  if (message.type === 'model') {
    currentModel = message.model;
    document.getElementById('status').textContent = 'Model v' + currentModel.schemaVersion;
    document.getElementById('tree').innerHTML = currentModel.root ? '<ul>' + renderNode(currentModel.root) + '</ul>' : '<p>No widget calls found.</p>';
    document.getElementById('diagnostics').innerHTML = (currentModel.diagnostics || []).length
      ? currentModel.diagnostics.map(d => '<p class="error">' + esc(d.message) + '</p>').join('')
      : '<span class="muted">No diagnostics.</span>';
    document.querySelectorAll('[data-id]').forEach(button => button.addEventListener('click', () => selectNode(button.dataset.id)));
    if (currentModel.root) selectNode(currentModel.root.id);
  } else if (message.type === 'error') {
    document.getElementById('status').textContent = 'Error';
    document.getElementById('tree').innerHTML = '<p class="error">' + esc(message.message) + '</p>';
  }
});
vscode.postMessage({type:'ready'});
</script>
</body>
</html>`;
  }
  dispose(): void {
    this.changeEmitter.dispose();

    for (const client of this.clients.values()) {
      client.dispose();
    }

    this.clients.clear();
  }

}

function getNonce(): string {
  let result = '';
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (let i = 0; i < 32; i++) result += chars.charAt(Math.floor(Math.random() * chars.length));
  return result;
}
