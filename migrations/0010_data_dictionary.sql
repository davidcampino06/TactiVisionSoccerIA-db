-- 0010 - Data dictionary inside the database: a description for every table and column.
-- Shown by psql \d+, the Neon console and scripts/data_dictionary.py (which writes docs/DICCIONARIO_DE_DATOS.md).
-- Comments are in Spanish because the documentation of the project is in Spanish. Idempotent.

COMMENT ON TABLE system_status IS 'Estado general de la plataforma (fila única de control).';
COMMENT ON COLUMN system_status.id IS 'Identificador.';
COMMENT ON COLUMN system_status.name IS 'Nombre del sistema.';
COMMENT ON COLUMN system_status.status IS 'Estado (ACTIVE).';

COMMENT ON TABLE users IS 'Cuentas de la plataforma: administradores, entrenadores y analistas.';
COMMENT ON COLUMN users.id IS 'Identificador (UUID).';
COMMENT ON COLUMN users.first_name IS 'Nombre.';
COMMENT ON COLUMN users.last_name IS 'Apellido.';
COMMENT ON COLUMN users.email IS 'Correo de inicio de sesión, único y en minúsculas.';
COMMENT ON COLUMN users.password_hash IS 'Hash bcrypt (costo 12) de la contraseña; nunca la contraseña.';
COMMENT ON COLUMN users.phone IS 'Teléfono opcional.';
COMMENT ON COLUMN users.profile_image_url IS 'Foto de perfil opcional.';
COMMENT ON COLUMN users.role IS 'ADMINISTRATOR, COACH o ANALYST.';
COMMENT ON COLUMN users.team_id IS 'Equipo al que pertenece un analista.';
COMMENT ON COLUMN users.is_active IS 'Falso si el administrador desactivó la cuenta.';
COMMENT ON COLUMN users.created_at IS 'Fecha de registro.';
COMMENT ON COLUMN users.updated_at IS 'Última modificación.';

COMMENT ON TABLE teams IS 'Equipos; cada entrenador tiene uno.';
COMMENT ON COLUMN teams.id IS 'Identificador.';
COMMENT ON COLUMN teams.coach_id IS 'Entrenador dueño del equipo (único).';
COMMENT ON COLUMN teams.name IS 'Nombre del equipo.';
COMMENT ON COLUMN teams.category IS 'Categoría (por ejemplo Sub-20).';
COMMENT ON COLUMN teams.city IS 'Ciudad.';
COMMENT ON COLUMN teams.description IS 'Descripción.';
COMMENT ON COLUMN teams.invitation_code IS 'Código para que un analista se una.';
COMMENT ON COLUMN teams.created_at IS 'Fecha de creación.';
COMMENT ON COLUMN teams.is_active IS 'Falso si el equipo fue desactivado.';

COMMENT ON TABLE players IS 'Plantilla de cada equipo.';
COMMENT ON COLUMN players.id IS 'Identificador.';
COMMENT ON COLUMN players.team_id IS 'Equipo actual (NULL si quedó sin equipo).';
COMMENT ON COLUMN players.first_name IS 'Nombre.';
COMMENT ON COLUMN players.last_name IS 'Apellido.';
COMMENT ON COLUMN players.shirt_number IS 'Dorsal (0 a 99).';
COMMENT ON COLUMN players.position IS 'GOALKEEPER, DEFENDER, MIDFIELDER o FORWARD.';
COMMENT ON COLUMN players.preferred_foot IS 'RIGHT, LEFT o BOTH.';
COMMENT ON COLUMN players.status IS 'ACTIVE, INJURED, SUSPENDED o INACTIVE.';
COMMENT ON COLUMN players.created_at IS 'Fecha de alta.';

COMMENT ON TABLE player_team_history IS 'Historial de equipos de cada jugador.';
COMMENT ON COLUMN player_team_history.id IS 'Identificador.';
COMMENT ON COLUMN player_team_history.player_id IS 'Jugador.';
COMMENT ON COLUMN player_team_history.team_id IS 'Equipo.';
COMMENT ON COLUMN player_team_history.joined_at IS 'Fecha de llegada.';
COMMENT ON COLUMN player_team_history.left_at IS 'Fecha de salida (NULL si sigue).';
COMMENT ON COLUMN player_team_history.withdrawal_reason IS 'Motivo de la salida.';

COMMENT ON TABLE matches IS 'Partidos de cada equipo.';
COMMENT ON COLUMN matches.id IS 'Identificador.';
COMMENT ON COLUMN matches.team_id IS 'Equipo.';
COMMENT ON COLUMN matches.opponent IS 'Rival.';
COMMENT ON COLUMN matches.is_home IS 'Verdadero si fue de local.';
COMMENT ON COLUMN matches.match_date IS 'Fecha y hora.';
COMMENT ON COLUMN matches.home_score IS 'Goles del equipo.';
COMMENT ON COLUMN matches.away_score IS 'Goles del rival.';
COMMENT ON COLUMN matches.result IS 'WIN, LOSS o DRAW (necesita ambos marcadores).';
COMMENT ON COLUMN matches.location IS 'Estadio o lugar.';
COMMENT ON COLUMN matches.status IS 'SCHEDULED, PLAYED o CANCELLED.';

COMMENT ON TABLE match_events IS 'Eventos registrados durante un partido.';
COMMENT ON COLUMN match_events.id IS 'Identificador.';
COMMENT ON COLUMN match_events.match_id IS 'Partido.';
COMMENT ON COLUMN match_events.minute IS 'Minuto.';
COMMENT ON COLUMN match_events.second IS 'Segundo (0 a 59).';
COMMENT ON COLUMN match_events.event_type IS 'Tipo: GOAL, SHOT, FOUL, CORNER, cartas, cambios...';
COMMENT ON COLUMN match_events.zone IS 'Zona de la cancha.';
COMMENT ON COLUMN match_events.source_x IS 'Posición horizontal opcional.';
COMMENT ON COLUMN match_events.source_y IS 'Posición vertical opcional.';
COMMENT ON COLUMN match_events.result IS 'Resultado del evento.';

COMMENT ON TABLE formations IS 'Catálogo compartido de formaciones (4-3-3, 4-4-2...).';
COMMENT ON COLUMN formations.id IS 'Identificador.';
COMMENT ON COLUMN formations.name IS 'Nombre único.';
COMMENT ON COLUMN formations.description IS 'Descripción.';
COMMENT ON COLUMN formations.player_count IS 'Jugadores (1 a 11).';
COMMENT ON COLUMN formations.created_at IS 'Fecha de creación.';

COMMENT ON TABLE match_formations IS 'Formaciones usadas en un partido.';
COMMENT ON COLUMN match_formations.id IS 'Identificador.';
COMMENT ON COLUMN match_formations.match_id IS 'Partido.';
COMMENT ON COLUMN match_formations.formation_id IS 'Formación.';

COMMENT ON TABLE tactical_plays IS 'Jugadas diseñadas en el editor táctico.';
COMMENT ON COLUMN tactical_plays.id IS 'Identificador.';
COMMENT ON COLUMN tactical_plays.team_id IS 'Equipo.';
COMMENT ON COLUMN tactical_plays.name IS 'Nombre.';
COMMENT ON COLUMN tactical_plays.description IS 'Descripción.';
COMMENT ON COLUMN tactical_plays.action_type IS 'BUILD_UP, PRESSING, COUNTER_ATTACK...';
COMMENT ON COLUMN tactical_plays.created_at IS 'Fecha de creación.';
COMMENT ON COLUMN tactical_plays.is_reusable IS 'Si se puede aplicar a otros partidos.';

COMMENT ON TABLE tactical_play_versions IS 'Versiones de cada jugada (patrón Prototype + pila de versiones).';
COMMENT ON COLUMN tactical_play_versions.id IS 'Identificador.';
COMMENT ON COLUMN tactical_play_versions.tactical_play_id IS 'Jugada.';
COMMENT ON COLUMN tactical_play_versions.created_by IS 'Usuario que la guardó.';
COMMENT ON COLUMN tactical_play_versions.version_number IS 'Número de versión (desde 1).';
COMMENT ON COLUMN tactical_play_versions.configuration_data IS 'JSON con jugadores y flechas.';
COMMENT ON COLUMN tactical_play_versions.created_at IS 'Fecha de la versión.';
COMMENT ON COLUMN tactical_play_versions.is_current IS 'Verdadero en la versión vigente.';

COMMENT ON TABLE match_tactical_plays IS 'Jugadas aplicadas a un partido.';
COMMENT ON COLUMN match_tactical_plays.id IS 'Identificador.';
COMMENT ON COLUMN match_tactical_plays.match_id IS 'Partido.';
COMMENT ON COLUMN match_tactical_plays.tactical_play_id IS 'Jugada.';

COMMENT ON TABLE videos IS 'Videos subidos a un partido.';
COMMENT ON COLUMN videos.id IS 'Identificador.';
COMMENT ON COLUMN videos.match_id IS 'Partido.';
COMMENT ON COLUMN videos.file_name IS 'Nombre original del archivo.';
COMMENT ON COLUMN videos.file_path IS 'Nombre con el que se guardó en el servidor.';
COMMENT ON COLUMN videos.format IS 'MP4, MOV, AVI, MKV o WEBM.';
COMMENT ON COLUMN videos.file_size IS 'Tamaño en bytes.';
COMMENT ON COLUMN videos.duration_seconds IS 'Duración opcional.';
COMMENT ON COLUMN videos.uploaded_at IS 'Fecha de subida.';
COMMENT ON COLUMN videos.status IS 'UPLOADED, ANALYZING o ANALYZED.';

COMMENT ON TABLE video_analyses IS 'Análisis de un video hechos por el servicio de IA.';
COMMENT ON COLUMN video_analyses.id IS 'Identificador.';
COMMENT ON COLUMN video_analyses.video_id IS 'Video analizado.';
COMMENT ON COLUMN video_analyses.status IS 'PENDING, PROCESSING, COMPLETED, FAILED o CANCELLED.';
COMMENT ON COLUMN video_analyses.analysis_mode IS 'REAL_VIDEO_ANALYSIS o SIMULATION_MODE.';
COMMENT ON COLUMN video_analyses.confidence_threshold IS 'Umbral de confianza de la detección.';
COMMENT ON COLUMN video_analyses.model_name IS 'Modelo de IA usado.';
COMMENT ON COLUMN video_analyses.model_version IS 'Versión del modelo.';
COMMENT ON COLUMN video_analyses.started_at IS 'Inicio.';
COMMENT ON COLUMN video_analyses.completed_at IS 'Fin.';
COMMENT ON COLUMN video_analyses.warning_message IS 'Advertencia o motivo del fallo.';
COMMENT ON COLUMN video_analyses.proximity_network IS 'JSON de la red de cercanía (grafo + BFS).';

COMMENT ON TABLE detections IS 'Jugadores y balón detectados en cada cuadro.';
COMMENT ON COLUMN detections.id IS 'Identificador.';
COMMENT ON COLUMN detections.video_analysis_id IS 'Análisis.';
COMMENT ON COLUMN detections.player_id IS 'Jugador asignado a la pista (opcional).';
COMMENT ON COLUMN detections.frame_number IS 'Cuadro del video.';
COMMENT ON COLUMN detections.timestamp IS 'Segundo del video.';
COMMENT ON COLUMN detections.object_type IS 'PLAYER o BALL.';
COMMENT ON COLUMN detections.confidence IS 'Confianza del detector (0 a 1).';
COMMENT ON COLUMN detections.bounding_box_x IS 'Caja: x.';
COMMENT ON COLUMN detections.bounding_box_y IS 'Caja: y.';
COMMENT ON COLUMN detections.bounding_box_width IS 'Caja: ancho.';
COMMENT ON COLUMN detections.bounding_box_height IS 'Caja: alto.';
COMMENT ON COLUMN detections.player_number IS 'Dorsal si se conoce.';
COMMENT ON COLUMN detections.track_id IS 'Pista del seguimiento (mismo jugador entre cuadros).';

COMMENT ON TABLE tactical_indicators IS 'Indicadores tácticos de cada análisis.';
COMMENT ON COLUMN tactical_indicators.id IS 'Identificador.';
COMMENT ON COLUMN tactical_indicators.video_analysis_id IS 'Análisis.';
COMMENT ON COLUMN tactical_indicators.name IS 'Nombre, por ejemplo team_a.team_width.';
COMMENT ON COLUMN tactical_indicators.value IS 'Valor promedio.';
COMMENT ON COLUMN tactical_indicators.unit IS 'Unidad (proporción de imagen, jugadores, pases...).';
COMMENT ON COLUMN tactical_indicators.calculated_at IS 'Fecha del cálculo.';
COMMENT ON COLUMN tactical_indicators.threshold IS 'Umbral de referencia (NULL si no tiene).';

COMMENT ON TABLE ai_recommendations IS 'Posibles problemas tácticos y recomendaciones de la IA.';
COMMENT ON COLUMN ai_recommendations.id IS 'Identificador.';
COMMENT ON COLUMN ai_recommendations.match_id IS 'Partido.';
COMMENT ON COLUMN ai_recommendations.title IS 'Posible problema.';
COMMENT ON COLUMN ai_recommendations.description IS 'Recomendación.';
COMMENT ON COLUMN ai_recommendations.severity IS 'HIGH, MEDIUM o LOW.';
COMMENT ON COLUMN ai_recommendations.confidence IS 'Confianza (0 a 1).';
COMMENT ON COLUMN ai_recommendations.evidence IS 'Datos que lo justifican.';
COMMENT ON COLUMN ai_recommendations.created_at IS 'Fecha.';
COMMENT ON COLUMN ai_recommendations.status IS 'GENERATED, REVIEWED, CONFIRMED o DISMISSED (revisión humana).';

COMMENT ON TABLE recommendation_indicators IS 'Indicadores que sustentan cada recomendación.';
COMMENT ON COLUMN recommendation_indicators.id IS 'Identificador.';
COMMENT ON COLUMN recommendation_indicators.recommendation_id IS 'Recomendación.';
COMMENT ON COLUMN recommendation_indicators.indicator_id IS 'Indicador.';

COMMENT ON TABLE reports IS 'Reportes generados (partido, análisis o evolución).';
COMMENT ON COLUMN reports.id IS 'Identificador.';
COMMENT ON COLUMN reports.team_id IS 'Equipo.';
COMMENT ON COLUMN reports.generated_by IS 'Usuario que lo generó.';
COMMENT ON COLUMN reports.title IS 'Título.';
COMMENT ON COLUMN reports.report_type IS 'MATCH, VIDEO_ANALYSIS o TEAM_EVOLUTION.';
COMMENT ON COLUMN reports.generated_at IS 'Fecha.';
COMMENT ON COLUMN reports.version IS 'Versión (desde 1).';
COMMENT ON COLUMN reports.snapshot_data IS 'JSON con los datos del reporte en ese momento.';

COMMENT ON TABLE notifications IS 'Notificaciones de cada equipo (la campana).';
COMMENT ON COLUMN notifications.id IS 'Identificador.';
COMMENT ON COLUMN notifications.team_id IS 'Equipo.';
COMMENT ON COLUMN notifications.event IS 'ANALYSIS_COMPLETED, TACTICAL_ALERT...';
COMMENT ON COLUMN notifications.analysis_id IS 'Análisis relacionado.';
COMMENT ON COLUMN notifications.match_id IS 'Partido relacionado.';
COMMENT ON COLUMN notifications.message IS 'Texto.';
COMMENT ON COLUMN notifications.created_at IS 'Fecha.';

COMMENT ON TABLE notification_reads IS 'Qué notificaciones leyó cada usuario.';
COMMENT ON COLUMN notification_reads.notification_id IS 'Notificación.';
COMMENT ON COLUMN notification_reads.user_id IS 'Usuario.';
COMMENT ON COLUMN notification_reads.read_at IS 'Fecha de lectura.';

COMMENT ON TABLE audit_log IS 'Auditoría: quién cambió qué y cuándo (escrita por triggers).';
COMMENT ON COLUMN audit_log.id IS 'Identificador.';
COMMENT ON COLUMN audit_log.table_name IS 'Tabla modificada.';
COMMENT ON COLUMN audit_log.row_id IS 'Fila modificada.';
COMMENT ON COLUMN audit_log.action IS 'INSERT, UPDATE o DELETE.';
COMMENT ON COLUMN audit_log.changed_by IS 'Usuario de la aplicación (app.current_user_id).';
COMMENT ON COLUMN audit_log.changed_at IS 'Fecha.';
COMMENT ON COLUMN audit_log.changed_fields IS 'Fila nueva, fila borrada o columnas cambiadas (sin contraseñas).';

COMMENT ON TABLE schema_migrations IS 'Historial de migraciones aplicadas.';
COMMENT ON COLUMN schema_migrations.version IS 'Nombre de la migración.';
COMMENT ON COLUMN schema_migrations.applied_at IS 'Fecha de aplicación.';

COMMENT ON VIEW v_match_summary IS 'Resumen por partido: marcador, videos, análisis y problemas abiertos.';
COMMENT ON VIEW v_analysis_indicators IS 'Indicadores de cada análisis completado con su partido y equipo.';
COMMENT ON VIEW v_player_participation IS 'Participación de cada jugador en los videos analizados.';
COMMENT ON VIEW v_open_issues IS 'Posibles problemas abiertos, el más urgente primero.';
