CREATE TABLE `partner_notices` (
	`user_id` text PRIMARY KEY,
	`reason` text NOT NULL,
	`at` integer NOT NULL,
	CONSTRAINT `fk_partner_notices_user_id_users_id_fk` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE
);
