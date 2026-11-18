# Enhanced SCCT Versus Community Maps
Enhanced SCCT Versus Community Maps is the repository of community-made maps for Splinter Cell: Chaos Theory's Versus mode. The map browser in [SCCT Versus Reloaded](https://allypal.github.io/SCCT_Versus_Reloaded/) (**Install Maps** in the map search dialog) lists every map here that a player does not have, and downloads and updates them.

## Submission Guidelines
- The map must be playable with little to no errors and support every game mode: Story, Disk Hunt, Deathmatch and Merc Deathmatch.
  - It is recommended to add extra PlayerStarts for Merc Deathmatch. 12 is a good amount for most maps. In the PlayerStart properties, set `bMercDeathMatchStart=True` to use it for that mode.
- `Textures\<Map>-i.utc` must include a map name as well as lobby and loading screen textures at minimum. Briefings are recommended.
- Include a sound bank (`Sounds\<Map>.uas`) with at least the win, lose and objective sounds.
- Include the editor copy (`MapsEd\<Map>.sdc`). It is not needed to play the map, but it is required so the map can be reviewed for any flaws during submission.
- Do not modify any packages from the stock game or those included with Enhanced SCCT Versus.
- Provide the authors, a short description and the recommended player count (1, 2, 4, 6 or 8).
- No pornographic, hateful or illegal material.
- Try to keep the map at 50 MB or under. Larger maps are considered case by case.

---

# Maintainer Guide
> [!NOTE]
> The following sections are for repository maintainers only. Map authors do not need to follow these steps, see [Submission Guidelines](#submission-guidelines) above.

## Repository Layout
- `maps/<Map>/map.json` describes one map, where `<Map>` is the map's package name.
- The map packages are uploaded as release assets, with one release per revision (`<Map>-r<N>`).
- `index.signed` lists every map for the browser. It is only written by `tools\Publish-Map.ps1` and is signed with a private key kept outside the repository. Reloaded rejects any index it did not sign.
- `prohibited.txt` lists every package name that ships with Enhanced SCCT Versus. Community maps cannot reuse any of these names.
- `official.txt` lists the official maps. Every player installs these automatically, keeps them up to date and cannot delete them, so they are not listed in the map browser. Only the repository owners edit this file, and a `map.json` cannot make itself official.

## Adding a Map
### Prepare the Files
Place the map's files in a folder laid out like the game's `Packages` folder:
- `Maps\<Map>.sdc` is the map itself.
- `MapsEd\<Map>.sdc` is the editor copy of the map.
- `Sounds\<Map>.uas` is the map's sound bank, with at least the win, lose and objective sounds.
- `Textures\<Map>-i.utc` is the map's `SMapSettings`: the map name, session parameters such as match length, team lives and respawn time, briefing text, and the map thumbnail, briefing and loading screen textures.
- Any other packages the map needs: textures (`Textures\*.utx`), static meshes (`StaticMeshes\*.usx`), sounds (`Sounds\*.uax`) or animations (`Animations\*.ukx`).

The first four are required.

### Write map.json
For a new map, create `maps/<Map>/map.json`:
```json
{
  "code": "FortX",
  "title": "Enhanced Fort X",
  "authors": ["Someone"],
  "description": "A few plain sentences.",
  "recommendedPlayers": 4,
  "playlists": ["Standard"],
  "variant": "Enhanced"
}
```
- `recommendedPlayers` is how many players the map suits, both teams together: 1 (a solo training map), 2 (1v1), 4 (2v2), 6 (3v3) or 8 (4v4).
- `playlists` (optional) are the playlists the map is added to on first install, such as `Standard`, `Extended`, `Classic`, `3v3` or `Merc Deathmatch`. Players without that playlist are skipped.
- `variant` (optional) is a word in the title that marks the map as a version of another map. On first install it is added to the player's variant words, so the map search dialog sorts the map next to the original. Leave it out for an original map.

### Add a Preview
Optionally add `maps/<Map>/preview.jpg`, the picture shown in the map browser. It must be a JPEG of at most 512x512 and 256 KB. JPEG does not support transparency, so the image should be solid. Players download it once, and again only when it changes.

### Publish
Run `tools\Publish-Map.ps1 -Code <Map> -Files <folder>`. It zips the packages, creates the release with the GitHub CLI, fills in the rest of `map.json` and re-signs the index. With `-Local`, the zip is placed under `releases\` instead, for testing with a local index. `tools\Publish-Map.ps1 -Code <Map> -Upload` then publishes that same revision.

Commit and push. The Validate workflow checks every map and the index.

## Updating a Map
- After editing a `map.json`, a `preview.jpg` or `official.txt`, run `tools\Publish-Map.ps1 -Reindex`. A new preview does not need a new revision.
- Publishing the map again creates a new revision. A new revision changes the map's packages, so players on different revisions cannot join each other until they update.

## Adding an Official Map
Before publishing, add the map's code to `official.txt`, and `Publish-Map.ps1` will sign it into the index as official. Every player installs it the next time the game starts, without a prompt, and keeps it up to date. Official maps cannot be deleted from Reloaded.

## Signing Key
`tools\Publish-Map.ps1 -NewKey` creates the signing key once, writes `signing-key.pub` and prints the `MapIndexSigningKey.h` that Reloaded.Core is built with. Back up the private key offline. If it is lost, a new Reloaded release is required before the browser accepts a new key.
