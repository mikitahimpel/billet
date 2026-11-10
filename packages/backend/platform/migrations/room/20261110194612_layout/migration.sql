CREATE TABLE `layout_log` (
	`change_id` text PRIMARY KEY,
	`position` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `placement` (
	`item_id` text PRIMARY KEY,
	`surface` text NOT NULL,
	`u` integer NOT NULL,
	`v` integer NOT NULL,
	`quarter_turns` integer NOT NULL,
	`position` integer NOT NULL
);
