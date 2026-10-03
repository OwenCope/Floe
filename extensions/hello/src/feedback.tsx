import { Action, ActionPanel, Form, showToast, Toast } from "@raycast/api";
import { useState } from "react";

type Values = { subject: string; body: string; urgent: boolean; area: string; due: Date | null; tags: string[] };

export default function Command() {
  const [subjectError, setSubjectError] = useState<string>();
  return (
    <Form
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Send"
            onSubmit={async (values: Values) => {
              if (!values.subject) {
                setSubjectError("Required");
                return;
              }
              const due = values.due instanceof Date ? values.due.toISOString().slice(0, 10) : "none";
              await showToast({
                style: Toast.Style.Success,
                title: `Sent: ${values.subject}`,
                message: `urgent=${values.urgent} area=${values.area} due=${due} tags=${values.tags.join("+")}`,
              });
            }}
          />
        </ActionPanel>
      }
    >
      <Form.Description title="Feedback" text="Every field type the launcher renders." />
      <Form.TextField id="subject" title="Subject" placeholder="What happened?" error={subjectError} onChange={() => setSubjectError(undefined)} />
      <Form.TextArea id="body" title="Details" />
      <Form.Checkbox id="urgent" title="Priority" label="Urgent" />
      <Form.Dropdown id="area" title="Area">
        <Form.Dropdown.Item value="ui" title="Interface" />
        <Form.Dropdown.Item value="runtime" title="Runtime" />
      </Form.Dropdown>
      <Form.DatePicker id="due" title="Due" type={Form.DatePicker.Type.Date} />
      <Form.TagPicker id="tags" title="Tags">
        <Form.TagPicker.Item value="bug" title="Bug" />
        <Form.TagPicker.Item value="idea" title="Idea" />
      </Form.TagPicker>
      <Form.Separator />
      <Form.FilePicker id="files" title="Attachments" />
    </Form>
  );
}
