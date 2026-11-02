const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

// CONFIGURACIÓN DE CONEXIÓN A POSTGRESQL
const pool = new Pool({
  user: 'postgres',
  host: 'localhost',
  database: 'postgres',
  password: 'tu_password_aqui', // <- Cambia esto si definiste una contraseña para postgres
  port: 5432,
});

// 1. Obtener tablas del Diccionario de Datos
app.get('/api/diccionario/tablas', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT table_schema, table_name 
      FROM information_schema.tables 
      WHERE table_type = 'BASE TABLE' 
        AND table_schema NOT IN ('pg_catalog', 'information_schema', 'autoaudit')
      ORDER BY table_name;
    `);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 2. Obtener columnas de una tabla del Diccionario de Datos
app.get('/api/diccionario/columnas', async (req, res) => {
  const { esquema, tabla } = req.query;
  try {
    const result = await pool.query(`
      SELECT column_name, data_type 
      FROM information_schema.columns
      WHERE table_schema = $1 AND table_name = $2
      ORDER BY ordinal_position;
    `, [esquema || 'public', tabla]);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 3. Registrar / Configurar Auditoría
app.post('/api/configurar', async (req, res) => {
  const { esquema, tabla, columna, operaciones } = req.body;
  try {
    for (const op of operaciones) {
      await pool.query('CALL autoaudit.sp_configurar_auditoria($1, $2, $3, $4)', [
        esquema || 'public',
        tabla,
        columna,
        op
      ]);
    }
    res.json({ message: 'Configuración guardada y trigger generado con éxito.' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 4. Consultar Bitácora Histórica
app.get('/api/bitacora', async (req, res) => {
  const { usuario, tabla, columna } = req.query;
  try {
    let query = `SELECT id_bitacora, fecha_hora, esquema_origen, tabla_origen, columna_afectada, operacion, identificador_registro, valor_anterior, valor_nuevo, usuario_db, ip_origen FROM autoaudit.bitacora_auditoria WHERE 1=1`;
    const params = [];

    if (usuario) {
      params.push(usuario);
      query += ` AND usuario_db = $${params.length}`;
    }
    if (tabla && columna) {
      params.push(tabla);
      query += ` AND tabla_origen = $${params.length}`;
      params.push(columna);
      query += ` AND columna_afectada = $${params.length}`;
    }

    query += ` ORDER BY fecha_hora DESC LIMIT 100;`;
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(3000, () => {
  console.log('Servidor AutoAudit corriendo en http://localhost:3000');
});