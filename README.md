# Enhanced SCCT Versus community maps

Community maps for Splinter Cell: Chaos Theory Versus. SCCT Versus Reloaded's map browser (**Install maps** in
the map search dialog) lists every map here that a player does not have, and downloads and updates them.

- `maps/<Code>/map.json` describes one map. `<Code>` is the map's package name.
- The packages themselves are release assets, one release per revision (`<Code>-r<N>`).
- `index.signed` lists every map for the browser. Only `tools\Publish-Map.ps1` writes it, signed with a key
  kept outside the repo; Reloaded rejects an index it did not sign.
- `prohibited.txt` lists every package name Enhanced ships. No community map may reuse one.
- `official.txt` lists the official maps, which every player installs and keeps up to date automatically
  and cannot delete. Only the repo owners edit it; a `map.json` cannot make itself official.

## Adding a map or a new revision

1. Put the map's packages in a folder: `<Code>.sdc`, `<Code>-i.utc`, and any textures, static meshes, sounds
   or animations it needs.
2. For a new map, write `maps/<Code>/map.json`:
   ```json
   {
     "code": "FortX",
     "title": "Enhanced Fort X",
     "authors": ["Someone"],
     "description": "A few plain sentences.",
     "game": "enhanced",
     "playlists": ["Standard"],
     "variant": "Enhanced"
   }
   ```
   - `game` is `enhanced`, or `any` for a map that also loads in stock Versus.
   - `playlists` (optional): playlists a first install adds the map to, by name, such as `Standard`,
     `Extended`, `Classic`, `3v3` or `Merc Deathmatch`. A player without that playlist is skipped.
   - `variant` (optional): a word in the title that marks it as a version of another map. A first install
     adds it to the player's variant words, so the map search dialog sorts the map with the original.
3. Optionally add `maps/<Code>/preview.jpg`, the picture the browser shows: a JPEG of at most 512x512 and
   256 KB. Players download it once, and again only when it changes.
4. Run `tools\Publish-Map.ps1 -Code FortX -Files <folder>`. It zips the packages, creates the release with
   the GitHub CLI, fills in the rest of `map.json` and re-signs the index.
5. Commit and push. The Validate workflow checks every map and the index.

After editing a `map.json`, a `preview.jpg` or `official.txt`, run `tools\Publish-Map.ps1 -Reindex`. A new
preview needs no new revision.

A new revision changes the map's package, so players on different revisions cannot join each other until
they update.

## Keys

`tools\Publish-Map.ps1 -NewKey` creates the signing key once, writes `signing-key.pub`, and prints the
`MapIndexSigningKey.h` that Reloaded.Core is built with. Back the private key up offline; losing it means
a Reloaded release before the browser accepts a new one.
