CREATE TABLE `list_items` (
	`id` text PRIMARY KEY,
	`list_id` text NOT NULL,
	`position` integer NOT NULL,
	`text` text NOT NULL,
	`author` text NOT NULL,
	`added_at` integer NOT NULL,
	`done_by` text,
	`done_at` integer,
	`quantity` text,
	`note` text,
	`icon` text,
	`aisle` text,
	`media_kind` text,
	`media_tmdb` integer,
	`country` text,
	`wants` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `list_keys` (
	`key` text PRIMARY KEY,
	`at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `lists` (
	`id` text PRIMARY KEY,
	`position` integer NOT NULL,
	`kind` text NOT NULL,
	`title` text NOT NULL,
	`icon_symbol` text NOT NULL,
	`icon_tint` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `list_items_list` ON `list_items` (`list_id`,`position`);--> statement-breakpoint
CREATE INDEX `list_keys_at` ON `list_keys` (`at`);