# Spade

Real-life side quests, dealt every day, week and month. Finish them to earn XP, dig up items, collect feats and build up your digger.

Spade is a dark, simple quest app with the feel of a late-90s 3D adventure game: chunky models, fog, a lantern, a big low moon, and dithered pixels.

![The quest board, the hero screen, an item being dug up, and the satchel](docs/screenshots.png)

This repository is the **web prototype**. It installs on an iPhone from Safari and runs full-screen and offline. A native Swift version is planned to follow it, using this one as the blueprint.

## How it plays

- **Quests.** Three daily, three weekly and two monthly quests are dealt from a built-in deck. Press and hold a quest to seal it.
- **Your own quests.** Write your own and either shuffle them into the deck or pin them so they show every time.
- **XP and levels.** Every quest pays XP. Each level asks for 50 more XP than the last.
- **Dig-ups.** Weekly and monthly quests always unearth an item. Daily quests sometimes do. There are 33 to find.
- **Feats.** 25 achievements, each watching one number such as "best streak".
- **Your digger.** Change skin, hair and scarf, and wear what you find.

The 3D scene doubles as a progress display:

| In the scene | What it shows |
| --- | --- |
| Lantern flame | Today's dailies. It grows as you finish them, and changes colour on long streaks. |
| Seven runes on the standing stone | The week, Monday at the bottom. A rune lights for each day you finish a daily. |
| Moon phase | The month. A sliver on the 1st, full on the last day. |

## Put it on an iPhone

1. Open the app's web address in **Safari**.
2. Tap **Share**, then **Add to Home Screen**.
3. Open Spade from its new icon. It now runs full-screen and works with no signal.

Progress is saved on the device only. Settings has **Copy save** and **Load save** for backing it up or moving it.

### Publishing it (one-time setup)

The workflow in `.github/workflows/pages.yml` tests, builds and publishes the app whenever `main` changes.

1. In the repository on GitHub, open **Settings → Pages**.
2. Set **Source** to **GitHub Actions**.

The app then appears at `https://<your-username>.github.io/spade-sidequests/`. Free GitHub Pages needs the repository to be public.

## Run it on a computer

You need [Node.js](https://nodejs.org) 20 or newer.

```bash
npm install
npm run dev       # start the app at http://localhost:5173
npm test          # run the game-rule tests
npm run build     # make the finished app in dist/
npm run preview   # try the finished app, with offline support
npm run icons     # redraw the app icons
```

While `npm run dev` is running, `http://localhost:5173/dev/stage.html` shows the 3D scene on its own, which is handy when tuning the art. For example: `dev/stage.html?view=hero&gear=hand:barrow_blade,head:straw_hat&month=1`.

## How the code is organised

```
src/
  content/   The game's data as plain JSON: quests, items, feats, colour palettes.
  game/      The rules. Pure TypeScript with no screen code at all.
  three/     The 3D scene: models, lighting, the dither effect, the dig-up.
  ui/        The screens.
  audio/     Sound effects, generated in code.
scripts/     Draws the app icons.
dev/         A test page for the 3D scene.
```

A few ideas hold it together:

- **Rules are separate from screens.** Everything in `src/game` is a plain function: it takes the current save and returns a new one, plus a list of what happened. That is why the rules can be tested without a phone (`src/game/game.test.ts`).
- **Models are data.** Nothing is loaded from a 3D model file. Each object is a short list of boxes, cylinders and balls (see `src/three/models`), like a LEGO instruction sheet.
- **Quests are dealt with a seeded shuffle.** The date is part of the seed, so today's quests are the same every time you open the app, and different tomorrow.
- **The look is a recipe.** Light is worked out at the corners of each triangle, textures are tiny and blurry, the scene is drawn small and enlarged with hard pixels, and a dither pattern fakes extra shades (`src/three/RetroMaterial.ts`, `src/three/post.ts`).

### Changing things

- **Add or edit quests:** `src/content/quests.json`.
- **Add an item:** describe it in `src/content/items.json`, then give it a model with the same id in `src/three/models/items.ts`. A test checks that every item has a model.
- **Add a feat:** `src/content/achievements.json`.
- **Rebalance XP, levels or loot odds:** `src/game/rewards.ts`.

## For the Swift version

These parts are meant to carry straight over:

| Prototype | Swift app |
| --- | --- |
| `src/content/*.json` | Load the same files unchanged. |
| `src/game/*.ts` | Port function by function. The tests describe the expected behaviour. |
| `src/three/models/*.ts` | The same part lists map onto `SCNBox`, `SCNCylinder`, `SCNCone` and `SCNSphere`. |
| Settings → Copy save | The save is plain JSON, so the native app can import it. |

Things the web version cannot do that the native one can: a notification when quests reset, haptic taps, and home-screen widgets.

## Credits

All models, textures, icons and sounds are generated by this project's own code.

Typefaces, under the SIL Open Font License:

- **Jacquard 24** and **Jersey 15** by Sarah Cadigan-Fried
- **IM Fell English** by Igino Marini
