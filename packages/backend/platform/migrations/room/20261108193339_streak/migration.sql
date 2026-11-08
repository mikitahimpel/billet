ALTER TABLE `room` ADD `streak_best` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `room` ADD `streak_last_day` text;--> statement-breakpoint
ALTER TABLE `room` ADD `streak_restored_on` text;