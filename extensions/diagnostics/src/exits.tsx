import { List } from "@raycast/api";
import { useEffect } from "react";

export default function Command() {
  useEffect(() => {
    console.error("about to exit with status 3");
    setTimeout(() => process.exit(3), 300);
  }, []);
  return <List isLoading />;
}
