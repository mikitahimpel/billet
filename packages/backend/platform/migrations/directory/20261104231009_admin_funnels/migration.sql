CREATE TABLE `admin_funnels` (
	`id` text PRIMARY KEY,
	`name` text NOT NULL,
	`definition` text NOT NULL,
	`created_at` integer NOT NULL,
	`created_by` text NOT NULL
);
