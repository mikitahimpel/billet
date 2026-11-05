CREATE TABLE `reaction` (
	`note_id` text NOT NULL,
	`by` text NOT NULL,
	`reaction` text,
	`at` integer NOT NULL,
	`rev` integer NOT NULL,
	CONSTRAINT `reaction_pk` PRIMARY KEY(`note_id`, `by`)
);
--> statement-breakpoint
ALTER TABLE `room` ADD `last_reaction_rev` integer;--> statement-breakpoint
CREATE UNIQUE INDEX `reaction_rev` ON `reaction` (`rev`);