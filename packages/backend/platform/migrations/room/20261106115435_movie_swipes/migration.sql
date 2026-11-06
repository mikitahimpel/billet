CREATE TABLE `movie_swipes` (
	`member` text NOT NULL,
	`title` text NOT NULL,
	`choice` text NOT NULL,
	`name` text NOT NULL,
	`poster_path` text,
	`at` integer NOT NULL,
	CONSTRAINT `movie_swipes_pk` PRIMARY KEY(`member`, `title`)
);
--> statement-breakpoint
CREATE INDEX `movie_swipes_at` ON `movie_swipes` (`at`);