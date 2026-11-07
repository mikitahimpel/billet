CREATE TABLE `riddle_guesses` (
	`riddle` text NOT NULL,
	`key` text NOT NULL,
	`right` integer NOT NULL,
	`at` integer NOT NULL,
	CONSTRAINT `riddle_guesses_pk` PRIMARY KEY(`riddle`, `key`)
);
--> statement-breakpoint
CREATE TABLE `riddle_series` (
	`id` integer PRIMARY KEY,
	`series` integer NOT NULL,
	`best` integer NOT NULL,
	CONSTRAINT "riddle_series_single_row" CHECK("id" = 1)
);
--> statement-breakpoint
CREATE TABLE `riddles` (
	`id` text PRIMARY KEY,
	`drawer` text NOT NULL,
	`ended_at` integer,
	`body` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `riddles_ended_at` ON `riddles` (`ended_at`);