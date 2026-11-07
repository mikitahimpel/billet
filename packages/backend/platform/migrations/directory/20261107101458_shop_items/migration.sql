CREATE TABLE `shop_item_changes` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`item_id` text NOT NULL,
	`at` integer NOT NULL,
	`by` text NOT NULL,
	`action` text NOT NULL,
	`before` text,
	`after` text
);
--> statement-breakpoint
CREATE TABLE `shop_items` (
	`id` text PRIMARY KEY,
	`kind` text NOT NULL,
	`name` text NOT NULL,
	`blurb` text,
	`mood` text,
	`rarity` text NOT NULL,
	`price` integer NOT NULL,
	`sale_price` integer,
	`sale_from` integer,
	`sale_until` integer,
	`deal_discount` real,
	`deal_order` integer,
	`section` text NOT NULL,
	`sort_order` integer NOT NULL,
	`plus` integer DEFAULT 0 NOT NULL,
	`is_new` integer DEFAULT 0 NOT NULL,
	`asset` text NOT NULL,
	`min_build` integer,
	`active` integer DEFAULT 1 NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	`created_at` integer NOT NULL,
	`created_by` text NOT NULL,
	`updated_at` integer NOT NULL,
	`updated_by` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `shop_item_changes_item_index` ON `shop_item_changes` (`item_id`,`id`);--> statement-breakpoint
CREATE INDEX `shop_items_order_index` ON `shop_items` (`sort_order`);--> statement-breakpoint
INSERT INTO `shop_items` (`id`, `kind`, `name`, `blurb`, `mood`, `rarity`, `price`, `sale_price`, `sale_from`, `sale_until`, `deal_discount`, `deal_order`, `section`, `sort_order`, `plus`, `is_new`, `asset`, `min_build`, `active`, `version`, `created_at`, `created_by`, `updated_at`, `updated_by`) VALUES
('armchair', 'furniture', 'Cloud Armchair', 'Big enough for two and a cat who insists.', 'Rested', 'epic', 320, NULL, NULL, NULL, NULL, NULL, 'furniture', 10, 0, 1, '{"_tag":"Bundled","id":"armchair"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('lamp', 'decor', 'Mushroom Lamp', 'Warm glow for late-night talks.', 'Rested', 'rare', 140, NULL, NULL, NULL, 0.25, 5, 'decor', 20, 0, 0, '{"_tag":"Bundled","id":"lamp"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('monstera', 'decor', 'Monstera', 'Grows a new leaf every week you visit.', NULL, 'common', 90, NULL, NULL, NULL, 0.3, 7, 'decor', 30, 0, 0, '{"_tag":"Bundled","id":"monstera"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('bookcase', 'furniture', 'Little Bookcase', 'Room for both your favourite stories.', NULL, 'epic', 260, NULL, NULL, NULL, 0.2, 3, 'furniture', 40, 0, 0, '{"_tag":"Bundled","id":"bookcase"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('rug', 'room', 'Woven Rug', 'Soft rings in honey and blush.', NULL, 'rare', 180, NULL, NULL, NULL, NULL, NULL, 'room', 50, 0, 0, '{"_tag":"Bundled","id":"rug"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('yarn', 'mochi', 'Yarn Ball', '{cat}''s favourite thing to unravel.', 'Curious', 'common', 60, NULL, NULL, NULL, 0.3, 1, 'mochi', 60, 0, 0, '{"_tag":"Bundled","id":"yarn"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('mouse', 'mochi', 'Toy Mouse', 'Squeaks a little. {cat} pretends not to care.', 'Curious', 'common', 45, NULL, NULL, NULL, 0.3, 4, 'mochi', 70, 0, 0, '{"_tag":"Bundled","id":"mouse"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('tower', 'mochi', 'Cat Tower', 'Two floors, one nap spot at the very top.', 'Happy', 'legendary', 540, NULL, NULL, NULL, NULL, NULL, 'mochi', 80, 1, 0, '{"_tag":"Bundled","id":"tower"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('print', 'decor', 'Sunset Print', 'The sky from your first evening walk.', NULL, 'rare', 120, NULL, NULL, NULL, 0.25, 8, 'decor', 90, 0, 0, '{"_tag":"Bundled","id":"print"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('teatable', 'furniture', 'Tea Table', 'Two cups, always.', NULL, 'rare', 210, NULL, NULL, NULL, 0.25, 0, 'furniture', 100, 0, 1, '{"_tag":"Bundled","id":"teatable"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('donutbed', 'mochi', 'Donut Bed', 'Sprinkles included, calories not.', 'Rested', 'epic', 380, NULL, NULL, NULL, 0.2, 6, 'mochi', 110, 0, 0, '{"_tag":"Bundled","id":"donutbed"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('lantern', 'room', 'Paper Lantern', 'Hangs by the window and hums with light.', NULL, 'legendary', 150, NULL, NULL, NULL, 0.2, 2, 'room', 120, 1, 0, '{"_tag":"Bundled","id":"lantern"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('ink-rose', 'ink', 'Rose', NULL, NULL, 'common', 60, NULL, NULL, NULL, NULL, NULL, 'inks', 1010, 0, 0, '{"_tag":"Bundled","id":"ink-rose"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('ink-sea', 'ink', 'Sea', NULL, NULL, 'common', 60, NULL, NULL, NULL, NULL, NULL, 'inks', 1020, 0, 0, '{"_tag":"Bundled","id":"ink-sea"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('ink-moss', 'ink', 'Moss', NULL, NULL, 'common', 60, NULL, NULL, NULL, NULL, NULL, 'inks', 1030, 0, 0, '{"_tag":"Bundled","id":"ink-moss"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('ink-ember', 'ink', 'Ember', NULL, NULL, 'common', 60, NULL, NULL, NULL, NULL, NULL, 'inks', 1040, 0, 0, '{"_tag":"Bundled","id":"ink-ember"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('ink-plum', 'ink', 'Plum', NULL, NULL, 'rare', 90, NULL, NULL, NULL, NULL, NULL, 'inks', 1050, 0, 0, '{"_tag":"Bundled","id":"ink-plum"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration'),
('ink-gold', 'ink', 'Gold', NULL, NULL, 'epic', 120, NULL, NULL, NULL, NULL, NULL, 'inks', 1060, 0, 0, '{"_tag":"Bundled","id":"ink-gold"}', NULL, 1, 1, 1794009600000, 'migration', 1794009600000, 'migration');
