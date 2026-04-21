export function bootRuntimeShell(): void {
  const mount = document.getElementById('app');
  if (!mount) {
    return;
  }

  mount.textContent = 'Eduvi offline runtime shell initialized.';
}
