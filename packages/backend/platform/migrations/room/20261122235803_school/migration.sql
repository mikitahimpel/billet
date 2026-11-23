CREATE TABLE `school_routines` (
	`member` text PRIMARY KEY,
	`steps` text NOT NULL,
	`at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `school_tricks` (
	`trick` text PRIMARY KEY,
	`stars` integer NOT NULL,
	`by` text NOT NULL,
	`at` integer NOT NULL
);
