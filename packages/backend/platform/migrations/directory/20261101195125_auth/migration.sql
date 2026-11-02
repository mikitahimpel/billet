CREATE TABLE `auth_challenges` (
	`nonce_hash` text PRIMARY KEY,
	`expires_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `devices` (
	`id` text PRIMARY KEY,
	`user_id` text NOT NULL,
	`created_at` integer NOT NULL,
	CONSTRAINT `fk_devices_user_id_users_id_fk` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`)
);
--> statement-breakpoint
CREATE TABLE `push_tokens` (
	`device_id` text NOT NULL,
	`kind` text NOT NULL,
	`environment` text NOT NULL,
	`token` text NOT NULL,
	`updated_at` integer NOT NULL,
	CONSTRAINT `push_tokens_pk` PRIMARY KEY(`device_id`, `kind`),
	CONSTRAINT `fk_push_tokens_device_id_devices_id_fk` FOREIGN KEY (`device_id`) REFERENCES `devices`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE `sessions` (
	`token_hash` text PRIMARY KEY,
	`device_id` text NOT NULL,
	`created_at` integer NOT NULL,
	`expires_at` integer NOT NULL,
	CONSTRAINT `fk_sessions_device_id_devices_id_fk` FOREIGN KEY (`device_id`) REFERENCES `devices`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE `users` (
	`id` text PRIMARY KEY,
	`apple_subject` text NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `auth_challenges_expires_at_index` ON `auth_challenges` (`expires_at`);--> statement-breakpoint
CREATE INDEX `devices_user_id_index` ON `devices` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `push_tokens_token_kind_unique` ON `push_tokens` (`token`,`kind`);--> statement-breakpoint
CREATE UNIQUE INDEX `sessions_device_id_unique` ON `sessions` (`device_id`);--> statement-breakpoint
CREATE INDEX `sessions_expires_at_index` ON `sessions` (`expires_at`);--> statement-breakpoint
CREATE UNIQUE INDEX `users_apple_subject_unique` ON `users` (`apple_subject`);