import { Action, ActionPanel, Detail, getPreferenceValues, openExtensionPreferences } from "@raycast/api";

type Preferences = { greeting: string; token?: string; shout: boolean };

export default function Command() {
  const { greeting, token, shout } = getPreferenceValues<Preferences>();
  const text = shout ? greeting.toUpperCase() : greeting;
  return (
    <Detail
      markdown={`# ${text}\n\nToken: ${token ? `set (${token.length} characters)` : "not set"}`}
      actions={
        <ActionPanel>
          <Action title="Open Extension Preferences" onAction={openExtensionPreferences} />
        </ActionPanel>
      }
    />
  );
}
