import { Clipboard, Icon, LaunchType, MenuBarExtra, environment, open, showHUD } from "@raycast/api";

export default function Command() {
  const now = new Date();
  const time = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
  const longDate = now.toLocaleDateString(undefined, { weekday: "long", year: "numeric", month: "long", day: "numeric" });
  if (environment.launchType === LaunchType.Background) {
    console.log("launched in background");
  } else {
    console.log("user initiated");
  }
  return (
    <MenuBarExtra icon={Icon.Clock} title={time}>
      <MenuBarExtra.Section title="Today">
        <MenuBarExtra.Item title={longDate} />
        <MenuBarExtra.Separator />
        <MenuBarExtra.Item
          title="Copy Time"
          onAction={async () => {
            await Clipboard.copy(time);
            await showHUD("Copied");
          }}
        />
      </MenuBarExtra.Section>
      <MenuBarExtra.Item title="Open Clock" onAction={() => open("/System/Applications/Clock.app")} />
    </MenuBarExtra>
  );
}
