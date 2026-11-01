CREATE TABLE `rate_limits` (
	`bucket` text NOT NULL,
	`window_start` integer NOT NULL,
	`count` integer NOT NULL,
	CONSTRAINT `rate_limits_pk` PRIMARY KEY(`bucket`, `window_start`)
);
--> statement-breakpoint
CREATE INDEX `rate_limits_window_start_index` ON `rate_limits` (`window_start`);