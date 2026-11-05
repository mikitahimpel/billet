CREATE TABLE `demo_partners` (
	`bot_id` text PRIMARY KEY,
	`owner_id` text NOT NULL UNIQUE,
	`created_at` integer NOT NULL,
	CONSTRAINT `fk_demo_partners_bot_id_users_id_fk` FOREIGN KEY (`bot_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
	CONSTRAINT `fk_demo_partners_owner_id_users_id_fk` FOREIGN KEY (`owner_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
);
