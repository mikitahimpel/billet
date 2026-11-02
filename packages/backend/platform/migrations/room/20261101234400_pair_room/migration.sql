-- A room created by the earlier raw-SQL store already has `room` and `note` with these columns and
-- its rows, and a `migration` table of its own; they are kept and adopted, not recreated.
CREATE TABLE IF NOT EXISTS `note` (
	`seq` integer PRIMARY KEY,
	`body` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `room` (
	`id` integer PRIMARY KEY,
	`pair_id` text NOT NULL,
	`first_user` text NOT NULL,
	`first_presence` text NOT NULL,
	`second_user` text NOT NULL,
	`second_presence` text NOT NULL,
	`last_seq` integer NOT NULL,
	`streak_days` integer NOT NULL,
	CONSTRAINT "room_single_row" CHECK("id" = 1)
);
--> statement-breakpoint
DROP TABLE IF EXISTS `room_probe`;
--> statement-breakpoint
DROP TABLE IF EXISTS `migration`;