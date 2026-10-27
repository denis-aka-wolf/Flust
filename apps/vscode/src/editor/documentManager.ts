import * as vscode from 'vscode';

export class FlustDocument implements vscode.CustomDocument {
  readonly uri: vscode.Uri;

  private constructor(uri: vscode.Uri) {
    this.uri = uri;
  }

  static async create(uri: vscode.Uri): Promise<FlustDocument> {
    return new FlustDocument(uri);
  }

  dispose(): void {
    // The document is currently read-only in the visual editor.
    // Source editing will be added in a later milestone.
  }
}
