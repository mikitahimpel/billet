CREATE TABLE `delivery` (
	`note_id` text NOT NULL,
	`lane` text NOT NULL,
	`status` text NOT NULL,
	`attempts` integer NOT NULL,
	`next_attempt_at` integer NOT NULL,
	CONSTRAINT `delivery_pk` PRIMARY KEY(`note_id`, `lane`)
);
