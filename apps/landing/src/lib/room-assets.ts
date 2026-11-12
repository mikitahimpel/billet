// The pre-encoded room renders, Mochi's loop and the close-ups in src/assets/room, by file name. Imported as URLs,
// not through the image service, so their bytes (and the loop's animation) ship as encoded, under a hashed name.
const files = import.meta.glob<string>("../assets/room/*", {
  eager: true,
  query: "?url",
  import: "default",
});

export function roomAsset(name: string): string {
  const url = files[`../assets/room/${name}`];
  if (url === undefined) {
    throw new Error(`No room asset named ${name} in src/assets/room`);
  }
  return url;
}
