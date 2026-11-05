CREATE TABLE `activity` (
	`id` text PRIMARY KEY,
	`sort_key` text NOT NULL,
	`at` integer NOT NULL,
	`doer_kind` text NOT NULL,
	`doer_user` text,
	`body` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `activity_read` (
	`user` text PRIMARY KEY,
	`up_to` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `activity_sort_key` ON `activity` (`sort_key`);--> statement-breakpoint
CREATE INDEX `activity_at` ON `activity` (`at`);