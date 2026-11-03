// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

extension RegionQualityNotes {
    /// Curated notes for every platform other than NES/SNES, each backed by a
    /// source page consulted on the date it carries.
    static let platformSeed: [RegionQualityNote] = [
        RegionQualityNote(
            gameFamily: "Super Mario 64",
            platform: "N64",
            alternateTitles: [],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese Shindou Edition (Rev 3) is a later re-release that fixes bugs, adds Rumble Pak support and removes the backwards long jump glitch; it also carries the English version's voice clips.",
            sourceURL: "https://en.wikipedia.org/wiki/Super_Mario_64",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Wave Race 64 - Kawasaki Jet Ski",
            platform: "N64",
            alternateTitles: [],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese Shindou revision adds rumble support, extra time-trial ghosts, remixed music and new announcer voice clips and sound effects that the other regions lack.",
            sourceURL: "https://gonintendo.com/contents/9177-wave-race-64-s-enhanced-japanese-version-is-playable-on-switch-adds-rumble-support",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Legend of Zelda, The - Ocarina of Time",
            platform: "N64",
            alternateTitles: ["Zelda no Densetsu - Toki no Ocarina"],
            recommendedRegion: "USA",
            tiedRegions: ["Japan"],
            reason: "NTSC revision 1.2 (USA Rev 2, Japan Rev 2) has the most bug and text fixes; the PAL release runs at 50Hz, which alters timing and physics. Note 1.2 also recolours Ganon's blood and replaces the Fire Temple chant, so purists may prefer earlier revisions.",
            sourceURL: "https://www.zeldaspeedruns.com/oot/generalknowledge/version-differences",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Pokemon Stadium",
            platform: "N64", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "USA",
            tiedRegions: ["Europe"],
            reason: "The international release supports all 151 Pokemon and has much more content, while the original Japanese Pocket Monsters Stadium is limited to 40 usable Pokemon.",
            sourceURL: "https://en.wikipedia.org/wiki/Pocket_Monsters_Stadium",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Animal Crossing",
            platform: "GameCube", // verify DAT title
            alternateTitles: ["Doubutsu no Mori e+", "Doubutsu no Mori+"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "Japan's Doubutsu no Mori e+ includes the Western changes and adds e-Reader villagers, extra furniture, creatures, songs, GBA minigames, SD card support and private islands found in no other version.",
            sourceURL: "https://nookipedia.com/wiki/DnMe%2B",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Phantasy Star",
            platform: "SEGA Master System",
            alternateTitles: [],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "Only the Japanese release plays the Yamaha FM Sound Unit soundtrack (an add-on never sold outside Japan); Western copies are limited to the standard sound chip.",
            sourceURL: "https://en.wikipedia.org/wiki/Phantasy_Star_(video_game)",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Streets of Rage 3",
            platform: "SEGA Genesis", // verify DAT title
            alternateTitles: ["Bare Knuckle III"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "Bare Knuckle III keeps the sub-boss Ash, the original bomb plot, the ruined-city bad ending and the revealing enemy outfits that the Western release removed or toned down, and its difficulty is far gentler than the very hard Western Normal setting.",
            sourceURL: "https://en.wikipedia.org/wiki/Streets_of_Rage_3",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Castlevania - Bloodlines",
            platform: "SEGA Genesis", // verify DAT title
            alternateTitles: ["Castlevania - The New Generation", "Vampire Killer"],
            recommendedRegion: "USA",
            tiedRegions: [],
            reason: "The North American release keeps the game's blood and violent imagery, which the PAL release (retitled The New Generation) had stripped out.",
            sourceURL: "https://en.wikipedia.org/wiki/Castlevania:_Bloodlines",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Mega Man - The Wily Wars",
            platform: "SEGA Genesis", // verify DAT title
            alternateTitles: ["Rockman Mega World"],
            recommendedRegion: "USA",
            tiedRegions: ["Japan"],
            reason: "The 60Hz NTSC release runs at full speed in animation, music and gameplay, while the 50Hz PAL release is noticeably slower; Japan, also NTSC, shares the full speed.",
            sourceURL: "https://www.rockman-corner.com/2019/05/mega-man-wily-wars-runs-at-60hz-on-sega.html",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Splatterhouse 2",
            platform: "SEGA Genesis", // verify DAT title
            alternateTitles: ["Splatterhouse Part 2"],
            recommendedRegion: "USA",
            tiedRegions: [],
            reason: "The English-language release adds a password system for continuing, which the Japanese version does not have.",
            sourceURL: "https://en.wikipedia.org/wiki/Splatterhouse_2",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Sonic Adventure",
            platform: "SEGA Dreamcast",
            alternateTitles: [],
            recommendedRegion: "USA",
            tiedRegions: ["Europe"],
            reason: "The original Japanese release shipped with many glitches; the international version was patched by Sonic Team USA and adds Chao daycare and downloadable content.",
            sourceURL: "https://en.wikipedia.org/wiki/Sonic_Adventure",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Skies of Arcadia",
            platform: "SEGA Dreamcast", // verify DAT title
            alternateTitles: ["Eternal Arcadia"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "Eternal Arcadia keeps the cigarette references, alcohol and Bellena's original outfit, plus the stronger Vigoro/Aika scenes that the Western release removed or toned down.",
            sourceURL: "https://en.wikipedia.org/wiki/Skies_of_Arcadia",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Resident Evil",
            platform: "Sony PlayStation",
            alternateTitles: ["Biohazard"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese original keeps the uncut opening movie (gore shots and Chris smoking) that the US and European releases trimmed, and it is the only one with a vocal ending theme.",
            sourceURL: "https://en.wikipedia.org/wiki/Resident_Evil_(1996_video_game)",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Castlevania - Symphony of the Night",
            platform: "Sony PlayStation", // verify DAT title
            alternateTitles: ["Akumajou Dracula X - Gekka no Yasoukyoku"],
            recommendedRegion: "USA",
            tiedRegions: ["Europe"],
            reason: "The Western releases fixed a crash bug present in the Japanese version, and added AI improvements and a sound test.",
            sourceURL: "https://en.wikipedia.org/wiki/Castlevania:_Symphony_of_the_Night",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Tekken 3",
            platform: "Sony PlayStation",
            alternateTitles: [],
            recommendedRegion: "USA",
            tiedRegions: ["Japan"],
            reason: "The NTSC releases run at 60 fps, while the PAL release is capped at 50 fps and plays at about 83% of NTSC speed.",
            sourceURL: "https://vandal.elespanol.com/noticia/1350716040/ps-classic-se-confirman-los-problemas-de-rendimiento-en-los-juegos-pal/",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Final Fantasy X",
            platform: "Sony PlayStation 2",
            alternateTitles: ["Final Fantasy X International"],
            recommendedRegion: "Europe",
            tiedRegions: ["Japan", "Australia"],
            reason: "The PAL releases and the Japanese International edition add Dark Aeons, the Penance superboss, an Expert Sphere Grid and a bonus DVD; the original North American release lacks them.",
            sourceURL: "https://en.wikipedia.org/wiki/Final_Fantasy_X",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Final Fantasy X-2",
            platform: "Sony PlayStation 2", // verify DAT title
            alternateTitles: ["Final Fantasy X-2 - International + Last Mission"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japan-only International + Last Mission edition adds two dresspheres, an extra Last Mission dungeon and monster capture of Final Fantasy X characters; the NA/PAL releases stayed on the original version.",
            sourceURL: "https://en.wikipedia.org/wiki/Final_Fantasy_X-2",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Final Fantasy XII",
            platform: "Sony PlayStation 2", // verify DAT title
            alternateTitles: ["Final Fantasy XII - International Zodiac Job System"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japan-only International Zodiac Job System edition has twelve job-specific license boards, controllable guests, a speed-up button, New Game+ and Trial Mode, while keeping the English voices and widescreen of the Western version.",
            sourceURL: "https://en.wikipedia.org/wiki/Final_Fantasy_XII",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Kingdom Hearts",
            platform: "Sony PlayStation 2", // verify DAT title
            alternateTitles: ["Kingdom Hearts - Final Mix"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japan-only Final Mix folds in the international additions (extra bosses, difficulty level) and adds new enemies, items, cutscenes and a sequel-setup boss.",
            sourceURL: "https://en.wikipedia.org/wiki/Kingdom_Hearts_Final_Mix",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Kingdom Hearts II",
            platform: "Sony PlayStation 2", // verify DAT title
            alternateTitles: ["Kingdom Hearts II - Final Mix+"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japan-only Final Mix+ expands the game with extra scenes and bundles a second disc with the 3D remake Re:Chain of Memories.",
            sourceURL: "https://en.wikipedia.org/wiki/Kingdom_Hearts_II",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "ICO",
            platform: "Sony PlayStation 2", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "Europe",
            tiedRegions: ["Japan"],
            reason: "The Japanese and European releases unlock a two-player mode controlling Yorda and add subtitles translating her language; the North American release has neither.",
            sourceURL: "https://en.wikipedia.org/wiki/Ico",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Metal Gear Solid 3 - Snake Eater",
            platform: "Sony PlayStation 2", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "Europe",
            tiedRegions: [],
            reason: "The European release adds European Extreme difficulty, Duel Mode, a demo theater and extra Snake vs. Monkey levels absent from the NA release, plus most of the Japanese camouflage.",
            sourceURL: "https://en.wikipedia.org/wiki/Metal_Gear_Solid_3:_Snake_Eater",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Metal Gear Solid 2 - Sons of Liberty",
            platform: "Sony PlayStation 2", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "Europe",
            tiedRegions: [],
            reason: "Europe carries the Japanese additions (Boss Survival, Casting Theater, starting questionnaire) plus a European Extreme difficulty and a making-of DVD that the original US release lacks.",
            sourceURL: "https://en.wikipedia.org/wiki/Metal_Gear_Solid_2:_Sons_of_Liberty",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Dragon Quest VIII - Journey of the Cursed King",
            platform: "Sony PlayStation 2", // verify DAT title
            alternateTitles: ["Dragon Quest VIII - Sora to Umi to Daichi to Norowareshi Hime"],
            recommendedRegion: "USA",
            tiedRegions: ["Europe"],
            reason: "The Western releases add voice acting, orchestral music, a new menu and (in the NA version at least) extra spells and attacks that the Japanese original lacks.",
            sourceURL: "https://en.wikipedia.org/wiki/Dragon_Quest_VIII",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Persona 2 - Innocent Sin",
            platform: "Sony PSP", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese PSP release lets you create custom quests in Climax Theater and planned extra downloadable episodes; the Western release cut both.",
            sourceURL: "https://en.wikipedia.org/wiki/Persona_2:_Innocent_Sin",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Dissidia - Final Fantasy",
            platform: "Sony PSP", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "USA",
            tiedRegions: [],
            reason: "The Western release is an enhanced version with an Arcade mode, extra moves and events, a shorter tutorial and English/Japanese battle voices; Japan only got this content later as Universal Tuning.",
            sourceURL: "https://en.wikipedia.org/wiki/Dissidia_Final_Fantasy",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Kingdom Hearts - Birth by Sleep",
            platform: "Sony PSP", // verify DAT title
            alternateTitles: ["Kingdom Hearts - Birth by Sleep Final Mix"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japan-only Final Mix includes the features added to the Western releases and a new secret episode for Aqua.",
            sourceURL: "https://en.wikipedia.org/wiki/Kingdom_Hearts_Birth_by_Sleep",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Crisis Core - Final Fantasy VII",
            platform: "Sony PSP",
            alternateTitles: [],
            recommendedRegion: "USA",
            tiedRegions: ["Europe"],
            reason: "The North American and European releases add a harder difficulty mode that the original Japanese release did not have.",
            sourceURL: "https://en.wikipedia.org/wiki/Crisis_Core:_Final_Fantasy_VII",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Metal Gear Solid - Portable Ops",
            platform: "Sony PSP", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "Europe",
            tiedRegions: [],
            reason: "The European release of the original game added maps, characters, missions and a Boss Rush mode that the other regions got only through the later Plus edition.",
            sourceURL: "https://en.wikipedia.org/wiki/Metal_Gear_Solid:_Portable_Ops",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Dead or Alive 3",
            platform: "Microsoft Xbox",
            alternateTitles: [],
            recommendedRegion: "Europe",
            tiedRegions: ["Japan"],
            reason: "The later Japanese and European releases add a new intro, more costumes, a dozen-plus new attacks and tougher, refined AI; the launch-window North American version has none of that.",
            sourceURL: "https://en.wikipedia.org/wiki/Dead_or_Alive_3",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Ninja Gaiden",
            platform: "Microsoft Xbox",
            alternateTitles: [],
            recommendedRegion: "USA",
            tiedRegions: ["Japan"],
            reason: "The original European release was cut to obtain a German rating, while the North American and Japanese versions keep the full gore and decapitations.",
            sourceURL: "https://en.wikipedia.org/wiki/Ninja_Gaiden_(2004_video_game)",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Metal Gear Solid",
            platform: "Game Boy Color", // verify DAT title
            alternateTitles: ["Metal Gear - Ghost Babel"],
            recommendedRegion: "Japan",
            tiedRegions: ["Europe"],
            reason: "The Japanese and European releases include the 13-part IdeaSpy 2.5 bonus story, unlocked via CODEC calls on a repeat playthrough, which the North American release lacks.",
            sourceURL: "https://en.wikipedia.org/wiki/Metal_Gear_Solid_(Game_Boy_Color)",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Super Mario Advance 4 - Super Mario Bros. 3",
            platform: "GBA",
            alternateTitles: ["Super Mario Advance 4 - Super Mario 3 + Mario Brothers"],
            recommendedRegion: "USA",
            tiedRegions: ["Japan"],
            reason: "The e-Reader level support works in the Japanese and North American releases, while in the European version it is present but disabled and not normally reachable.",
            sourceURL: "https://www.mariowiki.com/Super_Mario_Bros._3:_Super_Mario_Advance_4",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Mega Man - Battle Network 6 - Cybeast Gregar",
            platform: "GBA",
            alternateTitles: ["Rockman EXE 6 - Dennoujuu Gregar"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese release keeps the Boktai crossover scenario and the Beast Link Gate content, which were cut or disabled in the Western versions.",
            sourceURL: "https://en.wikipedia.org/wiki/Mega_Man_Battle_Network_6",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Mega Man - Battle Network 6 - Cybeast Falzar",
            platform: "GBA",
            alternateTitles: ["Rockman EXE 6 - Dennoujuu Falzar"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese release keeps the Boktai crossover scenario and the Beast Link Gate content, which were cut or disabled in the Western versions.",
            sourceURL: "https://en.wikipedia.org/wiki/Mega_Man_Battle_Network_6",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Mega Man Zero",
            platform: "GBA",
            alternateTitles: ["Rockman Zero"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese original has the full blood effects, which were toned down in the Western localizations.",
            sourceURL: "https://en.wikipedia.org/wiki/Mega_Man_Zero_(video_game)",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Final Fantasy IV",
            platform: "NDS", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese release plays the vocal song Tsuki no Akari over the ending credits, which international versions replaced with an in-game track.",
            sourceURL: "https://en.wikipedia.org/wiki/Final_Fantasy_IV_(2007_video_game)",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Mario Kart 64",
            platform: "N64",
            alternateTitles: [],
            recommendedRegion: "USA",
            tiedRegions: ["Japan"],
            reason: "The PAL release shows every NTSC frame on a 50Hz display, so the game runs at roughly five-sixths of the NTSC speed; the 60Hz NTSC releases (USA, Japan) keep the intended pace.",
            sourceURL: "https://speeddemosarchive.com/MarioKart64.html",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Yoshi's Story",
            platform: "N64",
            alternateTitles: ["Yoshi Story"],
            recommendedRegion: "USA",
            tiedRegions: ["Europe"],
            reason: "The international release cleaned up graphics and added white fences on the cardboard courses and extra secrets such as hidden coin formations that spell letters, none of which the original Japanese release has.",
            sourceURL: "https://en.wikipedia.org/wiki/Yoshi%27s_Story",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Mario Party 2",
            platform: "N64",
            alternateTitles: [],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese release keeps the revolver duel in the Western Land ending and Professor Fungi's pipe, both of which were altered or removed (toy guns, no pipe) in the international versions.",
            sourceURL: "https://www.mariowiki.com/Mario_Party_2",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Fire Emblem - Path of Radiance",
            platform: "GameCube", // verify DAT title
            alternateTitles: ["Fire Emblem - Souen no Kiseki"],
            recommendedRegion: "USA",
            tiedRegions: [],
            reason: "The Western releases fixed several Japanese bugs (forge critical error, Seraph Robe HP, Brave Bow drop) and tuned items and skills; the PAL disc defaults to 50Hz at five-sixths speed and drops progressive scan, so NTSC-U is the cleaner base, though Japan alone keeps Maniac mode.",
            sourceURL: "https://www.fireemblemwiki.org/wiki/List_of_version_differences/Fire_Emblem:_Path_of_Radiance",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Super Smash Bros. Brawl",
            platform: "Wii", // verify DAT title
            alternateTitles: ["Dairantou Smash Brothers X"],
            recommendedRegion: "Europe",
            tiedRegions: [],
            reason: "The PAL release corrects trophy text errors (such as Lyn's age and the Black Knight's sword), removes the Golden Hammer restriction on certain challenges and adds a skip in The Wilds of the Subspace Emissary.",
            sourceURL: "https://www.ssbwiki.com/Version_differences_(SSBB)",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "No More Heroes",
            platform: "Wii",
            alternateTitles: [],
            recommendedRegion: "USA",
            tiedRegions: [],
            reason: "The North American release keeps the game's gore, while the Japanese and European releases replace blood and dismemberment with black ash and toned-down deaths.",
            sourceURL: "https://www.engadget.com/2007-12-13-suda-51-approved-europes-bloodless-no-more-heroes.html",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Fire Emblem - Awakening",
            platform: "3DS", // verify DAT title
            alternateTitles: ["Fire Emblem - Kakusei"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "Japan keeps the uncovered Tharja swimsuit scene in the Summer Scramble DLC (covered by a curtain in the North American release), the mute-avatar option and Cordelia's cut dialogue line, all removed from Western localizations.",
            sourceURL: "https://www.fireemblemwiki.org/wiki/List_of_version_differences/Fire_Emblem_Awakening",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Xenoblade Chronicles X",
            platform: "Wii U", // verify DAT title
            alternateTitles: ["Xenoblade Cross"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese release has the bust-size slider in character creation and Lin's original revealing costumes, which the Western release removed or toned down.",
            sourceURL: "https://www.mcvuk.com/business-news/western-xenoblade-chronicles-x-does-away-with-boob-size-adjustment-slider/",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Tokyo Mirage Sessions #FE",
            platform: "Wii U", // verify DAT title
            alternateTitles: ["Genei Ibun Roku #FE"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese Wii U original keeps the uncensored outfits, underwear shots and original dungeon theme and received extra swimsuit DLC that the Western release altered or never got.",
            sourceURL: "https://www.imore.com/tokyo-mirage-sessions-fe-encore-censored",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Contra - Hard Corps",
            platform: "SEGA Genesis",
            alternateTitles: ["Contra - The Hard Corps", "Probotector"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese release adds a life gauge that absorbs several hits and gives unlimited continues, while the Western releases are one-hit and limit continues. The European Probotector build also swaps in robot characters, rewrites parts of the story and cuts one ending.",
            sourceURL: "https://en.wikipedia.org/wiki/Contra:_Hard_Corps",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Jet Grind Radio",
            platform: "SEGA Dreamcast", // verify DAT title
            alternateTitles: ["Jet Set Radio", "De La Jet Set Radio"],
            recommendedRegion: "USA",
            tiedRegions: ["Europe"],
            reason: "The overseas releases add extra stages (New York-based areas), playable characters and additional music that the original Japanese release lacks. The Japanese version keeps only an interactive credits sequence that the Western builds dropped.",
            sourceURL: "https://en.wikipedia.org/wiki/Jet_Set_Radio",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Resident Evil",
            platform: "SEGA Saturn",
            alternateTitles: ["Biohazard"],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese Saturn release is the most graphic version of the game (for example decapitated zombie heads stay on the floor), whereas the US release has censored live-action footage.",
            sourceURL: "https://en.wikipedia.org/wiki/Resident_Evil_(1996_video_game)",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Gran Turismo",
            platform: "Sony PlayStation",
            alternateTitles: [],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "The Japanese release contains two 1992 Honda NSX cars that were removed from the North American and European versions.",
            sourceURL: "https://en.wikipedia.org/wiki/Gran_Turismo_(1997_video_game)",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Final Fantasy VIII",
            platform: "Sony PlayStation",
            alternateTitles: [],
            recommendedRegion: "Japan",
            tiedRegions: [],
            reason: "Chocobo World is a PocketStation minigame, and the PocketStation was never sold outside Japan, so only Japanese owners can use it on the original hardware. The European release also had graphics altered (a Nazi-like uniform removed).",
            sourceURL: "https://en.wikipedia.org/wiki/Final_Fantasy_VIII",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Ninja Gaiden Sigma",
            platform: "Sony PlayStation 3", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "USA",
            tiedRegions: [],
            reason: "For the Japanese release Tecmo removed human beheadings to obtain a lower CERO rating, whereas the western releases keep the original's gore.",
            sourceURL: "https://en.wikipedia.org/wiki/Ninja_Gaiden_Sigma",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Fallout 3",
            platform: "Sony PlayStation 3", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "USA",
            tiedRegions: [],
            reason: "The Japanese version changed the Megaton quest so the bomb cannot be detonated and renamed the Fat Man weapon; other releases keep the original content.",
            sourceURL: "https://en.wikipedia.org/wiki/Fallout_3",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Fallout 3",
            platform: "Microsoft Xbox 360", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "USA",
            tiedRegions: [],
            reason: "The Japanese version changed the Megaton quest so the bomb cannot be detonated and renamed the Fat Man weapon; other releases keep the original content.",
            sourceURL: "https://en.wikipedia.org/wiki/Fallout_3",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Mortal Kombat vs. DC Universe",
            platform: "Sony PlayStation 3", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "Europe",
            tiedRegions: [],
            reason: "The European version shows the Joker and Deathstroke fatalities uncut, while the North American version cuts away before the gunshot to keep a Teen rating.",
            sourceURL: "https://en.wikipedia.org/wiki/Mortal_Kombat_vs._DC_Universe",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),
        RegionQualityNote(
            gameFamily: "Mortal Kombat vs. DC Universe",
            platform: "Microsoft Xbox 360", // verify DAT title
            alternateTitles: [],
            recommendedRegion: "Europe",
            tiedRegions: [],
            reason: "The European version shows the Joker and Deathstroke fatalities uncut, while the North American version cuts away before the gunshot to keep a Teen rating.",
            sourceURL: "https://en.wikipedia.org/wiki/Mortal_Kombat_vs._DC_Universe",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-26"
        ),

    ]
}
