/** App Store Connect screenshot specifications (iPhone), developer.apple.com/help/app-store-connect/reference/screenshot-specifications. */
export interface Size {
  id: string;
  width: number;
  height: number;
  group: string;
}

export const sizes: Size[] = [
  { id: "6.9-1320x2868", width: 1320, height: 2868, group: "iPhone 6.9 inch" },
  { id: "6.9-1290x2796", width: 1290, height: 2796, group: "iPhone 6.9 inch" },
  { id: "6.5-1284x2778", width: 1284, height: 2778, group: "iPhone 6.5 inch" },
  { id: "6.5-1242x2688", width: 1242, height: 2688, group: "iPhone 6.5 inch" },
];

export const defaultSizeIds = ["6.9-1320x2868", "6.5-1284x2778"];

/** The width the layout is drawn at; every size scales it by width and keeps the full height of its own ratio. */
export const designWidth = 1320;
