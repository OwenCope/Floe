import { Detail, LaunchProps } from "@raycast/api";

export default function Command(props: LaunchProps<{ arguments: { text: string; tone?: string } }>) {
  const { text, tone } = props.arguments;
  return <Detail markdown={`# ${tone === "loud" ? text.toUpperCase() : text}\n\nTone: ${tone ?? "none"}`} />;
}
