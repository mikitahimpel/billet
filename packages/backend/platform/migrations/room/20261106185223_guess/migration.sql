CREATE TABLE `guess_answers` (
	`day` text NOT NULL,
	`member` text NOT NULL,
	`question` integer NOT NULL,
	`option` integer NOT NULL,
	`at` integer NOT NULL,
	CONSTRAINT `guess_answers_pk` PRIMARY KEY(`day`, `member`, `question`)
);
--> statement-breakpoint
CREATE TABLE `guess_rounds` (
	`day` text PRIMARY KEY,
	`subject` text NOT NULL,
	`questions` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `guess_weeks` (
	`week` text NOT NULL,
	`member` text NOT NULL,
	`points` integer NOT NULL,
	CONSTRAINT `guess_weeks_pk` PRIMARY KEY(`week`, `member`)
);
