CREATE TABLE `invites` (
	`code_hash` text PRIMARY KEY,
	`owner_id` text NOT NULL,
	`created_at` integer NOT NULL,
	`expires_at` integer NOT NULL,
	CONSTRAINT `fk_invites_owner_id_users_id_fk` FOREIGN KEY (`owner_id`) REFERENCES `users`(`id`)
);
--> statement-breakpoint
CREATE TABLE `pair_members` (
	`user_id` text PRIMARY KEY,
	`pair_id` text NOT NULL,
	`created_at` integer NOT NULL,
	CONSTRAINT `fk_pair_members_user_id_users_id_fk` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `invites_owner_id_unique` ON `invites` (`owner_id`);--> statement-breakpoint
CREATE INDEX `invites_expires_at_index` ON `invites` (`expires_at`);--> statement-breakpoint
CREATE INDEX `pair_members_pair_id_index` ON `pair_members` (`pair_id`);