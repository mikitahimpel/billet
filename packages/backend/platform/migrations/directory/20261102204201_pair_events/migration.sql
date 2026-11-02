CREATE TABLE `pair_events` (
	`pair_id` text NOT NULL,
	`user_id` text NOT NULL,
	`name` text NOT NULL,
	`day` text NOT NULL,
	`count` integer NOT NULL,
	`first_at` integer NOT NULL,
	`last_at` integer NOT NULL,
	CONSTRAINT `pair_events_pk` PRIMARY KEY(`pair_id`, `user_id`, `name`, `day`)
);
--> statement-breakpoint
CREATE INDEX `pair_events_day_index` ON `pair_events` (`day`);