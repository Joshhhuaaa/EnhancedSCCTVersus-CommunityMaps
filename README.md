# Enhanced SCCT Versus community maps

Community maps for Splinter Cell: Chaos Theory Versus. SCCT Versus Reloaded's map browser (Settings → Maps)
lists every map here that a player does not have, and downloads and updates them.

- `maps/<Code>/map.json` describes one map. `<Code>` is the map's package name.
- The packages themselves are release assets, one release per revision (`<Code>-r<N>`).
- `index.signed` lists every map for the browser. Only `tools\Publish-Map.ps1` writes it, signed with a key
  kept outside the repo; Reloaded rejects an index it did not sign.
- `prohibited.txt` lists every package name Enhanced ships. No community map may reuse one.

## Adding a map or a new revision

1. Put the map's packages in a folder: `<Code>.sdc`, `<Code>-i.utc`, and any textures, static meshes, sounds
   or animations it needs.
2. For a new map, write `maps/<Code>/map.json`:
   ```json
   {
     "code": "FortX",
     "title": "Fort X",
     "authors": ["Someone"],
     "description": "A few plain sentences.",
     "game": "enhanced"
   }
   ```
   `game` is `enhanced`, or `any` for a map that also loads in stock Versus.
3. Run `tools\Publish-Map.ps1 -Code FortX -Files <folder>`. It zips the packages, creates the release with
   the GitHub CLI, fills in the rest of `map.json` and re-signs the index.
4. Commit and push. The Validate workflow checks every map and the index.

After editing a title or description by hand, run `tools\Publish-Map.ps1 -Reindex`.

A new revision changes the map's package, so players on different revisions cannot join each other until
they update.

## Keys

`tools\Publish-Map.ps1 -NewKey` creates the signing key once, writes `signing-key.pub`, and prints the
`MapIndexSigningKey.h` that Reloaded.Core is built with. Back the private key up offline; losing it means
a Reloaded release before the browser accepts a new one.
