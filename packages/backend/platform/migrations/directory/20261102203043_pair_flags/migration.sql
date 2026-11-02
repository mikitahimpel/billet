CREATE TABLE `pair_flags` (
	`pair_id` text NOT NULL,
	`experiment_key` text NOT NULL,
	`variant` text NOT NULL,
	`assigned_at` integer NOT NULL,
	CONSTRAINT `pair_flags_pk` PRIMARY KEY(`pair_id`, `experiment_key`)
);
