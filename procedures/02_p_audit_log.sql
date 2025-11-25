PROCEDURE p_audit_log(
    p_player_id  IN players.player_id%TYPE,
    p_game_id    IN games.game_id%TYPE,
    p_event_msg  IN audit_log.event_msg%TYPE
) IS PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO audit_log (
        player_id, 
        game_id, 
        event_msg
    )
    VALUES (
        p_player_id, 
        p_game_id, 
        SUBSTR(p_event_msg, 1, 2000)
    );
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN NULL;
END p_audit_log;
