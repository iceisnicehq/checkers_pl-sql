CREATE INDEX idx_games_status ON games(status);
CREATE INDEX idx_games_players ON games(player_white_id, player_black_id);
CREATE INDEX idx_games_puzzle_id ON games(puzzle_id);
CREATE INDEX idx_game_moves_game_id ON game_moves(game_id);
CREATE INDEX idx_player_ratings_main ON player_ratings(season_id, rule_id, rating DESC);