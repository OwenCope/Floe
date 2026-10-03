import { Clipboard, showHUD } from "@raycast/api";

export default async function Command() {
  const today = new Date().toISOString().slice(0, 10);
  await Clipboard.copy(today);
  await showHUD(`Copied ${today}`);
}
