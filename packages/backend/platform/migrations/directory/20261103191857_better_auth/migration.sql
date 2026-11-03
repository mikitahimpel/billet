CREATE TABLE `account_keys` (
	`key_hash` text PRIMARY KEY,
	`user_id` text NOT NULL,
	`created_at` integer NOT NULL,
	CONSTRAINT `fk_account_keys_user_id_users_id_fk` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE `auth_account` (
	`id` text PRIMARY KEY,
	`account_id` text NOT NULL,
	`provider_id` text NOT NULL,
	`user_id` text NOT NULL,
	`access_token` text,
	`refresh_token` text,
	`id_token` text,
	`access_token_expires_at` text,
	`refresh_token_expires_at` text,
	`scope` text,
	`password` text,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	CONSTRAINT `fk_auth_account_user_id_auth_user_id_fk` FOREIGN KEY (`user_id`) REFERENCES `auth_user`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE `auth_session` (
	`id` text PRIMARY KEY,
	`token` text NOT NULL,
	`user_id` text NOT NULL,
	`device_id` text NOT NULL,
	`expires_at` text NOT NULL,
	`ip_address` text,
	`user_agent` text,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	CONSTRAINT `fk_auth_session_user_id_auth_user_id_fk` FOREIGN KEY (`user_id`) REFERENCES `auth_user`(`id`) ON DELETE CASCADE,
	CONSTRAINT `fk_auth_session_device_id_devices_id_fk` FOREIGN KEY (`device_id`) REFERENCES `devices`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE `auth_user` (
	`id` text PRIMARY KEY,
	`name` text NOT NULL,
	`email` text NOT NULL,
	`email_verified` integer NOT NULL,
	`image` text,
	`is_anonymous` integer,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `auth_verification` (
	`id` text PRIMARY KEY,
	`identifier` text NOT NULL,
	`value` text NOT NULL,
	`expires_at` text NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
-- Moves every account to Better Auth. Nobody signs in again: `sessions.token_hash` is SHA-256 of
-- the token the app holds, which is exactly what `auth_session.token` keeps, so each session moves
-- as it is, with its device and expiry. Every existing user signed in with Apple, so each is linked.
-- Emails are made up, as for every user; Better Auth requires one and no real one is kept.
INSERT INTO `auth_user` (`id`, `name`, `email`, `email_verified`, `image`, `is_anonymous`, `created_at`, `updated_at`)
SELECT `id`, '', lower(hex(randomblob(16))) || '@apple.billet.invalid', 0, NULL, 0, strftime('%Y-%m-%dT%H:%M:%fZ', `created_at` / 1000.0, 'unixepoch'), strftime('%Y-%m-%dT%H:%M:%fZ', `created_at` / 1000.0, 'unixepoch')
FROM `users`;--> statement-breakpoint
INSERT INTO `auth_account` (`id`, `account_id`, `provider_id`, `user_id`, `created_at`, `updated_at`)
SELECT lower(hex(randomblob(16))), `apple_subject`, 'apple', `id`, strftime('%Y-%m-%dT%H:%M:%fZ', `created_at` / 1000.0, 'unixepoch'), strftime('%Y-%m-%dT%H:%M:%fZ', `created_at` / 1000.0, 'unixepoch')
FROM `users`;--> statement-breakpoint
INSERT INTO `auth_session` (`id`, `token`, `user_id`, `device_id`, `expires_at`, `created_at`, `updated_at`)
SELECT lower(hex(randomblob(16))), `sessions`.`token_hash`, `devices`.`user_id`, `sessions`.`device_id`, strftime('%Y-%m-%dT%H:%M:%fZ', `sessions`.`expires_at` / 1000.0, 'unixepoch'), strftime('%Y-%m-%dT%H:%M:%fZ', `sessions`.`created_at` / 1000.0, 'unixepoch'), strftime('%Y-%m-%dT%H:%M:%fZ', `sessions`.`created_at` / 1000.0, 'unixepoch')
FROM `sessions` INNER JOIN `devices` ON `devices`.`id` = `sessions`.`device_id`;--> statement-breakpoint
DROP INDEX IF EXISTS `sessions_device_id_unique`;--> statement-breakpoint
DROP INDEX IF EXISTS `sessions_expires_at_index`;--> statement-breakpoint
DROP INDEX IF EXISTS `users_apple_subject_unique`;--> statement-breakpoint
CREATE INDEX `account_keys_user_id_index` ON `account_keys` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `auth_account_provider_account_unique` ON `auth_account` (`provider_id`,`account_id`);--> statement-breakpoint
CREATE INDEX `auth_account_user_id_index` ON `auth_account` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `auth_session_token_unique` ON `auth_session` (`token`);--> statement-breakpoint
CREATE UNIQUE INDEX `auth_session_device_id_unique` ON `auth_session` (`device_id`);--> statement-breakpoint
CREATE INDEX `auth_session_user_id_index` ON `auth_session` (`user_id`);--> statement-breakpoint
CREATE INDEX `auth_session_expires_at_index` ON `auth_session` (`expires_at`);--> statement-breakpoint
CREATE UNIQUE INDEX `auth_user_email_unique` ON `auth_user` (`email`);--> statement-breakpoint
CREATE INDEX `auth_verification_identifier_index` ON `auth_verification` (`identifier`);--> statement-breakpoint
DROP TABLE `sessions`;--> statement-breakpoint
ALTER TABLE `users` DROP COLUMN `apple_subject`;