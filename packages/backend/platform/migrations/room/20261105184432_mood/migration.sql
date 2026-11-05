CREATE TABLE `mood` (
	`user` text PRIMARY KEY,
	`mood` text NOT NULL,
	`note` text,
	`at` integer NOT NULL
);
