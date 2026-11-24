# Test DATs

Sample DAT files for trying ROMForge without hunting them down first. **They are for testing only.** ROMForge does not need them to work, and they go stale: a DAT is a snapshot, and its publisher releases new ones all the time.

## What these files are

A DAT is a list of names, sizes and checksums (CRC32/MD5/SHA-1) that describes a set of dumps. These files contain **no ROMs, no disc images and no game data**. Each file is stored exactly as its publisher distributed it (including its header, author list and version); only the file names were tidied and the Wii U (Digital) DAT was zipped to save space. `manifest.json` lists every file with its source, source URL and SHA-256, so any file can be compared against a fresh download.

| File | Source |
|---|---|
| `nintendo/Nintendo - Game Boy Advance (20260929-130236).dat` | No-Intro |
| `nintendo/Nintendo - GameCube (2026-06-13 18-14-01).dat` | Redump |
| `nintendo/Nintendo - Nintendo 3DS (Decrypted) (20261103-092522).dat` | No-Intro |
| `nintendo/Nintendo - Nintendo 64 (BigEndian) (20261002-141522).dat` | No-Intro |
| `nintendo/Nintendo - Nintendo DS (Decrypted) (20261026-060331).dat` | No-Intro |
| `nintendo/Nintendo - Nintendo Entertainment System (Headered) (20260929-024435).dat` | No-Intro |
| `nintendo/Nintendo - Super Nintendo Entertainment System (20261001-100404).dat` | No-Intro |
| `nintendo/Nintendo - Wii U - WUX (2026-08-29 15-52-43).dat` | Redump |
| `nintendo/Nintendo - Wii (2026-06-15 03-13-28).dat` | Redump |
| `nintendo/Nintendo - Nintendo 3DS (Encrypted) (20261027-215731).dat` | No-Intro |
| `nintendo/Nintendo - Nintendo Entertainment System (Headerless) (20261001-004706).dat` | No-Intro |
| `nintendo/Nintendo - Wii U (Digital) (CDN) (20261029-045701).dat.zip` | No-Intro |
| `sega/Non-Redump - Sega - Sega Saturn (20260306-190347).zip` | Redump |
| `sega/Sega - 32X (20261010-152927).zip` | No-Intro |
| `sega/Sega - Dreamcast - Datfile (1516) (2026-06-14 18-25-41).zip` | Redump |
| `sega/Sega - Mega CD & Sega CD - Datfile (549) (2026-05-28 18-06-58).zip` | Redump |
| `sega/Sega - Mega Drive - Genesis (20261105-230705).zip` | No-Intro |

Sources: [No-Intro](https://www.no-intro.org) (DAT-o-MATIC) and [Redump](https://redump.info/). The Sega Saturn file comes from Redump's "Non-Redump" section.

## Licensing and ownership

- **These files are not covered by ROMForge's GPLv3 license.** They belong to their respective projects and contributors; they are only copied here, unmodified, as test data. Contributor names are kept in each file's own header.
- **Redump** says on its [About page](https://redump.info/about) that it only stores metadata and that this metadata "is considered public domain to be used however people see fit". That is its own statement, not a formal license text.
- **No-Intro** publishes its DATs through DAT-o-MATIC. Its Data Usage License was reported (secondhand, by a third-party project) to allow free use and redistribution for any lawful purpose without attribution. The license text could not be retrieved directly while preparing this folder, so treat the No-Intro terms as **unverified** and read the current license on the DAT-o-MATIC site before redistributing these files anywhere else.
- ROMForge is not affiliated with, endorsed by or sponsored by No-Intro or Redump. Game titles and brand names mentioned in the DATs belong to their owners.
- The files are provided "as is", with no warranty of any kind.

## For real use, download the current DATs

Get up-to-date DATs from the official sources above (No-Intro's are distributed as `.zip`; ROMForge accepts a `.zip` or `.dat`). Do not rely on these copies for an actual collection audit.

## Removal requests

If you maintain one of these databases, or are a contributor to one, and want a file removed from this repository, open an issue and it will be removed promptly.
