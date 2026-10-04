import { LaunchType, LocalStorage, environment, showHUD } from "@raycast/api";

export default async function Command() {
  const current = (await LocalStorage.getItem<number>("ticks")) ?? 0;
  const n = current + 1;
  await LocalStorage.setItem("ticks", n);
  if (environment.launchType === LaunchType.UserInitiated) {
    await showHUD(`Ticked ${n} times`);
  } else {
    console.log(`Ticked ${n} times in background`);
  }
}
