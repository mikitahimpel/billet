CREATE TABLE `cat` (
	`id` integer PRIMARY KEY,
	`name` text NOT NULL,
	`model` text NOT NULL,
	`coat` text NOT NULL,
	`born_at` integer NOT NULL,
	`nature_seed` text NOT NULL,
	`utc_offset_seconds` integer NOT NULL,
	`curious` real NOT NULL,
	`lazy` real NOT NULL,
	`cuddly` real NOT NULL,
	`last_seq` integer NOT NULL,
	`last_at` integer,
	CONSTRAINT "cat_single_row" CHECK("id" = 1)
);
--> statement-breakpoint
CREATE TABLE `cat_entry` (
	`seq` integer PRIMARY KEY,
	`id` text NOT NULL,
	`by` text NOT NULL,
	`at` integer NOT NULL,
	`body` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `cat_entry_id` ON `cat_entry` (`id`);--> statement-breakpoint
CREATE INDEX `cat_entry_at` ON `cat_entry` (`at`);