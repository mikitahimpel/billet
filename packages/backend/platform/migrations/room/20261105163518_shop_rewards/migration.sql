CREATE TABLE `claimed_bonus` (
	`collection_id` text PRIMARY KEY,
	`position` integer NOT NULL
);
--> statement-breakpoint
ALTER TABLE `room` ADD `gift_day` text;--> statement-breakpoint
ALTER TABLE `room` ADD `welcomed` integer DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE `wallet` ADD `lists` integer DEFAULT 0 NOT NULL;