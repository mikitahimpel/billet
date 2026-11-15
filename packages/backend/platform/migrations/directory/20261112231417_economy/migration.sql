CREATE TABLE `economy_days` (
	`day` text NOT NULL,
	`source` text NOT NULL,
	`credited` integer NOT NULL,
	`debited` integer NOT NULL,
	`entries` integer NOT NULL,
	CONSTRAINT `economy_days_pk` PRIMARY KEY(`day`, `source`)
);
--> statement-breakpoint
CREATE TABLE `economy_pair_days` (
	`pair_id` text NOT NULL,
	`day` text NOT NULL,
	`earned` integer NOT NULL,
	`balance` integer NOT NULL,
	`last_at` integer NOT NULL,
	`capped_care` integer NOT NULL,
	`capped_notes` integer NOT NULL,
	`capped_games` integer NOT NULL,
	`capped_lists` integer NOT NULL,
	CONSTRAINT `economy_pair_days_pk` PRIMARY KEY(`pair_id`, `day`)
);
--> statement-breakpoint
CREATE INDEX `economy_pair_days_day_index` ON `economy_pair_days` (`day`);