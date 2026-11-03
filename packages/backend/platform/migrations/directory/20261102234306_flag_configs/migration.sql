CREATE TABLE `flag_changes` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`key` text NOT NULL,
	`at` integer NOT NULL,
	`by` text NOT NULL,
	`action` text NOT NULL,
	`pair_id` text,
	`before` text,
	`after` text
);
--> statement-breakpoint
CREATE TABLE `flag_configs` (
	`key` text PRIMARY KEY,
	`config` text NOT NULL,
	`version` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`updated_by` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `pair_flag_overrides` (
	`pair_id` text NOT NULL,
	`experiment_key` text NOT NULL,
	`variant` text NOT NULL,
	`set_at` integer NOT NULL,
	`set_by` text NOT NULL,
	CONSTRAINT `pair_flag_overrides_pk` PRIMARY KEY(`pair_id`, `experiment_key`)
);
--> statement-breakpoint
CREATE INDEX `flag_changes_key_index` ON `flag_changes` (`key`,`id`);