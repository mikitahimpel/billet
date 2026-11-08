CREATE TABLE `review_changes` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`at` integer NOT NULL,
	`by` text NOT NULL,
	`action` text NOT NULL,
	`last_four` text
);
--> statement-breakpoint
CREATE TABLE `review_codes` (
	`code_hash` text PRIMARY KEY,
	`partner_id` text NOT NULL,
	`last_four` text NOT NULL,
	`created_at` integer NOT NULL,
	`created_by` text NOT NULL,
	`expires_at` integer NOT NULL,
	`revoked_at` integer,
	`claims` integer DEFAULT 0 NOT NULL,
	`last_claimed_at` integer,
	CONSTRAINT `fk_review_codes_partner_id_users_id_fk` FOREIGN KEY (`partner_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE `review_partners` (
	`user_id` text PRIMARY KEY,
	`created_at` integer NOT NULL,
	CONSTRAINT `fk_review_partners_user_id_users_id_fk` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
ALTER TABLE `partner_reports` ADD `note_id` text;