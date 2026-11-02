-- =====================================================
-- PROYECTO: AutoAudit - Sistema de Auditoría
-- AUTOR: Javier García
-- INSTITUCIÓN: Universidad Mariano Gálvez
-- =====================================================

CREATE SCHEMA IF NOT EXISTS autoaudit;

CREATE TABLE IF NOT EXISTS autoaudit.bitacora_auditoria (
    id_bitacora SERIAL PRIMARY KEY,
    fecha_hora TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    tabla_origen VARCHAR(100) NOT NULL,
    columna_afectada VARCHAR(100) NOT NULL,
    operacion VARCHAR(10) NOT NULL,
    valor_anterior TEXT,
    valor_nuevo TEXT,
    usuario_db VARCHAR(100) DEFAULT CURRENT_USER
);

-- Procedimiento Almacenado para generación dinámica de Triggers
CREATE OR REPLACE PROCEDURE autoaudit.sp_configurar_auditoria(
    p_esquema VARCHAR,
    p_tabla VARCHAR,
    p_columna VARCHAR,
    p_operaciones VARCHAR[]
)
LANGUAGE plpgsql AS $$
DECLARE
    v_trigger_name TEXT;
    v_func_name TEXT;
    v_events TEXT := '';
    v_op TEXT;
BEGIN
    v_trigger_name := 'trg_audit_' || p_tabla || '_' || p_columna;
    v_func_name := 'autoaudit.fn_audit_' || p_tabla || '_' || p_columna;

    EXECUTE format('
        CREATE OR REPLACE FUNCTION %I() RETURNS TRIGGER AS $fn$
        BEGIN
            IF TG_OP = ''INSERT'' THEN
                INSERT INTO autoaudit.bitacora_auditoria(tabla_origen, columna_afectada, operacion, valor_anterior, valor_nuevo)
                VALUES (%L, %L, ''INSERT'', NULL, CAST(NEW.%I AS TEXT));
            ELSIF TG_OP = ''UPDATE'' THEN
                IF OLD.%I IS DISTINCT FROM NEW.%I THEN
                    INSERT INTO autoaudit.bitacora_auditoria(tabla_origen, columna_afectada, operacion, valor_anterior, valor_nuevo)
                    VALUES (%L, %L, ''UPDATE'', CAST(OLD.%I AS TEXT), CAST(NEW.%I AS TEXT));
                END IF;
            ELSIF TG_OP = ''DELETE'' THEN
                INSERT INTO autoaudit.bitacora_auditoria(tabla_origen, columna_afectada, operacion, valor_anterior, valor_nuevo)
                VALUES (%L, %L, ''DELETE'', CAST(OLD.%I AS TEXT), NULL);
            END IF;
            RETURN NEW;
        END;
        $fn$ LANGUAGE plpgsql;',
        v_func_name, p_tabla, p_columna, p_columna, p_columna, p_tabla, p_columna, p_columna, p_columna, p_tabla, p_columna, p_columna
    );

    FOREACH v_op IN ARRAY p_operaciones LOOP
        IF v_events != '' THEN v_events := v_events || ' OR '; END IF;
        v_events := v_events || v_op;
    END LOOP;

    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I;', v_trigger_name, p_esquema, p_tabla);
    EXECUTE format('CREATE TRIGGER %I AFTER %s ON %I.%I FOR EACH ROW EXECUTE FUNCTION %I();',
        v_trigger_name, v_events, p_esquema, p_tabla, v_func_name
    );
END;
$$;