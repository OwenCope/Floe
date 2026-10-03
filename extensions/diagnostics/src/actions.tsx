import { Action, ActionPanel, Icon, List, showToast } from "@raycast/api";

export default function Command() {
  return (
    <List>
      <List.Item
        title="Item with nested actions"
        actions={
          <ActionPanel>
            <Action title="Primary" onAction={() => showToast({ title: "primary" })} />
            <ActionPanel.Section title="Copy">
              <Action.CopyToClipboard title="Copy Title" content="title" />
              <Action.CopyToClipboard title="Copy Link" content="link" />
            </ActionPanel.Section>
            <ActionPanel.Submenu title="Set Priority" icon={Icon.Tag}>
              <Action title="High" onAction={() => showToast({ title: "high" })} />
              <Action title="Low" onAction={() => showToast({ title: "low" })} />
            </ActionPanel.Submenu>
          </ActionPanel>
        }
      />
    </List>
  );
}
