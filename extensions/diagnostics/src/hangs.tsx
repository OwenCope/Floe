import { List } from "@raycast/api";
import { useEffect } from "react";

export default function Command() {
  useEffect(() => {
    setTimeout(() => {
      for (;;) {} // never yields, so the host can't answer pings
    }, 300);
  }, []);
  return <List isLoading />;
}
