import { List } from "@raycast/api";
import { useEffect } from "react";

export default function Command() {
  useEffect(() => {
    Promise.reject(new Error("Request failed on purpose"));
  }, []);
  return (
    <List>
      <List.Item title="Still rendering after the rejection" />
    </List>
  );
}
