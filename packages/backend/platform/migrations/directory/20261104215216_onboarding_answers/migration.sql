CREATE TABLE `onboarding_answers` (
	`user_id` text NOT NULL,
	`step_id` text NOT NULL,
	`version` text NOT NULL,
	`kind` text NOT NULL,
	`option_ids` text,
	`value` integer,
	`text` text,
	`answered_at` integer NOT NULL,
	CONSTRAINT `onboarding_answers_pk` PRIMARY KEY(`user_id`, `step_id`),
	CONSTRAINT `fk_onboarding_answers_user_id_users_id_fk` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE INDEX `onboarding_answers_step_index` ON `onboarding_answers` (`step_id`);