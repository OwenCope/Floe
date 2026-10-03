import { Action, ActionPanel, Color, Detail, Icon, List, showToast, Toast } from "@raycast/api";
import { useState } from "react";

const planets = [
  { name: "Mercury", kind: "Rocky", moons: 0, au: 0.39 },
  { name: "Venus", kind: "Rocky", moons: 0, au: 0.72 },
  { name: "Earth", kind: "Rocky", moons: 1, au: 1.0 },
  { name: "Mars", kind: "Rocky", moons: 2, au: 1.52 },
  { name: "Jupiter", kind: "Gas giant", moons: 95, au: 5.2 },
  { name: "Saturn", kind: "Gas giant", moons: 146, au: 9.58 },
  { name: "Uranus", kind: "Ice giant", moons: 28, au: 19.2 },
  { name: "Neptune", kind: "Ice giant", moons: 16, au: 30.05 },
];

function PlanetDetail({ planet }: { planet: (typeof planets)[number] }) {
  const markdown = `# ${planet.name}\n\nA **${planet.kind.toLowerCase()}** planet, ${planet.au} AU from the Sun.\n\n- Moons: ${planet.moons}\n- Type: ${planet.kind}\n\n\`\`\`\ndistance = ${planet.au} AU\n\`\`\``;
  return (
    <Detail
      markdown={markdown}
      navigationTitle={planet.name}
      actions={
        <ActionPanel>
          <Action.CopyToClipboard title="Copy Name" content={planet.name} />
          <Action.OpenInBrowser url={`https://en.wikipedia.org/wiki/${planet.name}_(planet)`} />
        </ActionPanel>
      }
    />
  );
}

export default function Command() {
  const [favorites, setFavorites] = useState<string[]>([]);
  const kinds = [...new Set(planets.map((planet) => planet.kind))];
  return (
    <List searchBarPlaceholder="Search planets…">
      {kinds.map((kind) => (
        <List.Section key={kind} title={kind}>
          {planets
            .filter((planet) => planet.kind === kind)
            .map((planet) => (
              <List.Item
                key={planet.name}
                icon={favorites.includes(planet.name) ? { source: Icon.Star, tintColor: Color.Yellow } : Icon.Globe}
                title={planet.name}
                subtitle={`${planet.au} AU`}
                accessories={[{ text: `${planet.moons} moons` }]}
                actions={
                  <ActionPanel>
                    <Action.Push title="Show Details" icon={Icon.Sidebar} target={<PlanetDetail planet={planet} />} />
                    <Action
                      title={favorites.includes(planet.name) ? "Remove Favorite" : "Add Favorite"}
                      icon={Icon.Star}
                      onAction={async () => {
                        setFavorites((current) =>
                          current.includes(planet.name) ? current.filter((name) => name !== planet.name) : [...current, planet.name],
                        );
                        await showToast({ style: Toast.Style.Success, title: "Favorites updated", message: planet.name });
                      }}
                    />
                    <Action.CopyToClipboard content={planet.name} />
                  </ActionPanel>
                }
              />
            ))}
        </List.Section>
      ))}
    </List>
  );
}
