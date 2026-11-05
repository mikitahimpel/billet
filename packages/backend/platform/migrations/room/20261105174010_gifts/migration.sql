CREATE TABLE `gift_loves` (
	`user` text PRIMARY KEY,
	`body` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `gift_plan` (
	`wish_id` text NOT NULL,
	`giver` text NOT NULL,
	`stage` text NOT NULL,
	CONSTRAINT `gift_plan_pk` PRIMARY KEY(`wish_id`, `giver`)
);
--> statement-breakpoint
CREATE TABLE `gift_wish` (
	`id` text PRIMARY KEY,
	`owner` text NOT NULL,
	`title` text NOT NULL,
	`link` text NOT NULL,
	`price` text NOT NULL,
	`note` text NOT NULL,
	`most_wanted` integer NOT NULL,
	`added_at` integer NOT NULL,
	`received_at` integer,
	`gifted_by` text
);
