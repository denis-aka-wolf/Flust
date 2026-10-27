export type WebviewMessage =
  | { type: 'ready' }
  | { type: 'revealSource'; offset: number };

export type ExtensionMessage =
  | { type: 'model'; model: unknown }
  | { type: 'error'; message: string };
